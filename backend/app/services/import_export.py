import asyncio
import io
import secrets
from enum import Enum
from typing import Any

import pandas as pd
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import Category, Product, ProductImage
from app.schemas.product import ImportReport, ImportRowError, ProductImportRow
from app.services import images

MAX_ROWS = 50_000
MAX_DOWNLOADS = 300  # фото по чужим ссылкам за один файл — дольше запрос не держим

# Колонки выгрузки: заголовок в файле → поле. Тот же файл после правки загружается обратно
EXPORT_COLUMNS = {
    "Артикул": "sku",
    "Название": "name",
    "Фасовка": "unit",
    "Категория": "category",
    "Бренд": "brand",
    "Себестоимость": "cost_price",
    "Цена": "retail_price",
    "Старая цена": "compare_at_price",
    "Оптовая цена": "wholesale_price",
    "Остаток": "stock",
    "В продаже": "is_active",
    "Фото": "image_url",
    "Описание": "description",
}
COLUMN_ALIASES = {
    **{k.lower(): v for k, v in EXPORT_COLUMNS.items()},
    **{v: v for v in EXPORT_COLUMNS.values()},
    "вес": "unit",
    "опт": "wholesale_price",
    "активен": "is_active",
    "ссылка на фото": "image_url",
    "фото (ссылка)": "image_url",
}
REQUIRED_COLUMNS = {"name", "retail_price"}


class FileFormat(str, Enum):
    XLSX = "xlsx"
    CSV = "csv"


class ImportFileError(ValueError):
    """Ошибка уровня файла (не строки) → HTTP 422."""


# Магические байты: проверяем содержимое, а не только расширение/Content-Type
_XLSX_MAGIC = b"PK\x03\x04"


def detect_format(filename: str, head: bytes) -> FileFormat:
    name = filename.lower()
    if name.endswith(".xlsx"):
        if not head.startswith(_XLSX_MAGIC):
            raise ImportFileError("Файл не похож на настоящий .xlsx")
        return FileFormat.XLSX
    if name.endswith(".csv"):
        if b"\x00" in head:
            raise ImportFileError("В CSV-файле двоичные данные")
        return FileFormat.CSV
    raise ImportFileError("Поддерживаются только .xlsx и .csv")


def _read_dataframe(content: bytes, fmt: FileFormat) -> pd.DataFrame:
    """CPU-bound: вызывается в отдельном потоке, чтобы не блокировать event loop."""
    buf = io.BytesIO(content)
    if fmt is FileFormat.XLSX:
        # dtype=str — не даём pandas «угадывать» типы (артикул 00123 → 123). Типы приводит Pydantic.
        df = pd.read_excel(buf, engine="openpyxl", dtype=str, nrows=MAX_ROWS + 1)
    else:
        df = pd.read_csv(buf, dtype=str, sep=None, engine="python", encoding="utf-8-sig", nrows=MAX_ROWS + 1)
    if len(df) > MAX_ROWS:
        raise ImportFileError(f"Слишком много строк (максимум {MAX_ROWS})")
    df.columns = [COLUMN_ALIASES.get(str(c).strip().lower(), str(c).strip().lower()) for c in df.columns]
    missing = REQUIRED_COLUMNS - set(df.columns)
    if missing:
        names = {v: k for k, v in EXPORT_COLUMNS.items()}
        raise ImportFileError("В файле нет колонок: " + ", ".join(names[m] for m in sorted(missing)))
    df = df.dropna(how="all")
    return df.astype(object).where(df.notna(), None)


def _fmt_errors(exc: ValidationError) -> list[str]:
    names = {v: k for k, v in EXPORT_COLUMNS.items()}
    out = []
    for e in exc.errors():
        field = names.get(str(e["loc"][0]), "") if e["loc"] else ""
        msg = e["msg"].removeprefix("Value error, ")
        out.append(f"{field}: {msg}" if field else msg)
    return out


def _key(name: str, unit: str | None) -> tuple[str, str]:
    return " ".join(name.lower().split()), " ".join((unit or "").lower().split())


def _new_sku(taken: set[str]) -> str:
    while (sku := f"FT-{secrets.token_hex(3).upper()}") in taken:
        pass
    taken.add(sku)
    return sku


class ProductImportService:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def _category(self, name: str, cache: dict[str, Category], dry_run: bool) -> Category | None:
        from app.web.catalog import slugify

        key = name.strip().lower()
        if key in cache:
            return cache[key]
        if dry_run:
            return None
        slug, n = slugify(name), 1
        while await self.session.scalar(select(Category.id).where(Category.slug == slug)):
            n += 1
            slug = f"{slugify(name)}-{n}"
        cat = Category(name=name.strip(), slug=slug)
        self.session.add(cat)
        await self.session.flush()
        cache[key] = cat
        return cat

    async def import_file(self, filename: str, content: bytes, *, dry_run: bool = False) -> ImportReport:
        fmt = detect_format(filename, content[:8])
        df = await asyncio.to_thread(_read_dataframe, content, fmt)
        present = set(df.columns)

        products = list((await self.session.scalars(select(Product))).unique().all())
        by_sku = {p.sku: p for p in products}
        by_key = {_key(p.name, p.unit): p for p in products}
        categories = {c.name.lower(): c for c in (await self.session.scalars(select(Category))).all()}
        taken_skus = set(by_sku)

        errors: list[ImportRowError] = []
        warnings: list[str] = []
        created = updated = downloaded = 0
        seen: set[int] = set()

        for idx, raw in enumerate(df.to_dict(orient="records")):
            file_row = idx + 2  # +1 заголовок, +1 нумерация с единицы
            try:
                row = ProductImportRow.model_validate(raw)
            except ValidationError as exc:
                errors.append(
                    ImportRowError(row=file_row, sku=raw.get("sku"), name=raw.get("name"), errors=_fmt_errors(exc))
                )
                continue

            product = (by_sku.get(row.sku) if row.sku else None) or by_key.get(_key(row.name, row.unit))
            if product is not None and id(product) in seen:
                warnings.append(f"Строка {file_row}: «{row.name}» уже был выше в файле — применена последняя строка")
            cost = row.cost_price if row.cost_price is not None else (product.cost_price if product else None)
            if cost is not None and row.retail_price < cost:
                warnings.append(f"Строка {file_row}: «{row.name}» продаётся дешевле себестоимости")

            if product is None:
                if row.cost_price is None:
                    warnings.append(f"Строка {file_row}: у нового товара «{row.name}» нет себестоимости — записан 0")
                created += 1
                if dry_run:
                    continue
                sku = row.sku if row.sku and row.sku not in taken_skus else _new_sku(taken_skus)
                taken_skus.add(sku)
                product = Product(
                    sku=sku,
                    name=row.name,
                    unit=row.unit,
                    cost_price=row.cost_price or 0,
                    retail_price=row.retail_price,
                    stock=0,
                    description="",
                )
                self.session.add(product)
                by_key[_key(row.name, row.unit)] = product
            else:
                updated += 1
                if dry_run:
                    continue
            seen.add(id(product))

            product.retail_price = row.retail_price
            if row.cost_price is not None:
                product.cost_price = row.cost_price
            if "compare_at_price" in present:
                product.compare_at_price = row.compare_at_price
            if "wholesale_price" in present:
                product.wholesale_price = row.wholesale_price  # пустая ячейка — оптовой цены нет
            for field in ("stock", "is_active", "brand", "description"):
                if (value := getattr(row, field)) is not None:
                    setattr(product, field, value)
            if row.category:
                product.category = await self._category(row.category, categories, dry_run)

            if row.image_url and not images.is_own(row.image_url):
                if downloaded >= MAX_DOWNLOADS:
                    warnings.append(f"Строка {file_row}: фото не скачано — за раз не больше {MAX_DOWNLOADS} фото")
                    continue
                try:
                    url, _, _ = images.store(await images.download(row.image_url), "products")
                except (images.ImageError, OSError) as exc:
                    warnings.append(f"Строка {file_row}: фото «{row.name}» не загружено — {exc}")
                    continue
                product.images = [ProductImage(url=url, position=0)]
                downloaded += 1

        if not dry_run:
            await self.session.flush()

        return ImportReport(
            total_rows=len(df),
            created=created,
            updated=updated,
            images_downloaded=downloaded,
            failed=len(errors),
            dry_run=dry_run,
            errors=errors[:500],
            warnings=warnings[:500],
        )

    async def export(self, fmt: FileFormat) -> bytes:
        base = get_settings().public_shop_url.rstrip("/")
        rows = (await self.session.scalars(select(Product).order_by(Product.name))).unique().all()
        records = []
        for p in rows:
            image = p.images[0].url if p.images else None
            records.append(
                {
                    "Артикул": p.sku,
                    "Название": p.name,
                    "Фасовка": p.unit,
                    "Категория": p.category.name if p.category else None,
                    "Бренд": p.brand,
                    "Себестоимость": float(p.cost_price),
                    "Цена": float(p.retail_price),
                    "Старая цена": float(p.compare_at_price) if p.compare_at_price is not None else None,
                    "Оптовая цена": float(p.wholesale_price) if p.wholesale_price is not None else None,
                    "Остаток": p.stock,
                    "В продаже": "да" if p.is_active else "нет",
                    "Фото": f"{base}{image}" if image and image.startswith("/") else image,
                    "Описание": p.description,
                }
            )
        return await asyncio.to_thread(_write_dataframe, records, fmt)


def _neutralize_formula(v):
    """CSV/Formula injection: «=HYPERLINK(…)» в названии товара Excel выполнил бы как формулу. Экранируем апострофом."""
    if isinstance(v, str) and v[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + v
    return v


def _write_dataframe(records: list[dict[str, Any]], fmt: FileFormat) -> bytes:
    df = pd.DataFrame.from_records(records, columns=list(EXPORT_COLUMNS)).map(_neutralize_formula)
    buf = io.BytesIO()
    if fmt is FileFormat.XLSX:
        with pd.ExcelWriter(buf, engine="openpyxl") as writer:
            df.to_excel(writer, index=False, sheet_name="Товары")
            sheet = writer.sheets["Товары"]
            for col, width in zip("ABCDEFGHIJKLM", (12, 36, 10, 20, 18, 14, 10, 12, 13, 10, 10, 50, 40), strict=True):
                sheet.column_dimensions[col].width = width
            sheet.freeze_panes = "A2"
    else:
        df.to_csv(buf, index=False, encoding="utf-8-sig")
    return buf.getvalue()
