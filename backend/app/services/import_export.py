import asyncio
import io
from collections.abc import Iterable
from enum import Enum
from typing import Any

import pandas as pd
from pydantic import ValidationError

from app.repositories.product import ProductRepository
from app.schemas.product import ImportReport, ImportRowError, ProductImportRow

BATCH_SIZE = 500
MAX_ROWS = 50_000
EXPORT_COLUMNS = [
    "sku",
    "name",
    "description",
    "cost_price",
    "retail_price",
    "compare_at_price",
    "wholesale_price",
    "stock",
    "is_active",
    "category_id",
]
REQUIRED_COLUMNS = {"sku", "name", "cost_price", "retail_price"}

# Синонимы заголовков — менеджеры часто присылают файлы с русскими колонками
COLUMN_ALIASES = {
    "артикул": "sku",
    "название": "name",
    "описание": "description",
    "себестоимость": "cost_price",
    "цена": "retail_price",
    "старая цена": "compare_at_price",
    "оптовая цена": "wholesale_price",
    "опт": "wholesale_price",
    "остаток": "stock",
    "активен": "is_active",
    "категория": "category_id",
}


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
            raise ImportFileError("File is not a valid .xlsx archive")
        return FileFormat.XLSX
    if name.endswith(".csv"):
        if b"\x00" in head:
            raise ImportFileError("CSV contains binary data")
        return FileFormat.CSV
    raise ImportFileError("Only .xlsx and .csv are supported")


def _read_dataframe(content: bytes, fmt: FileFormat) -> pd.DataFrame:
    """CPU-bound: вызывается в отдельном потоке, чтобы не блокировать event loop."""
    buf = io.BytesIO(content)
    if fmt is FileFormat.XLSX:
        # dtype=str — не даём pandas «угадывать» типы (артикул 00123 → 123). Типы приводит Pydantic.
        df = pd.read_excel(buf, engine="openpyxl", dtype=str, nrows=MAX_ROWS + 1)
    else:
        df = pd.read_csv(buf, dtype=str, sep=None, engine="python", encoding="utf-8-sig", nrows=MAX_ROWS + 1)
    if len(df) > MAX_ROWS:
        raise ImportFileError(f"Too many rows (max {MAX_ROWS})")
    df.columns = [COLUMN_ALIASES.get(str(c).strip().lower(), str(c).strip().lower()) for c in df.columns]
    missing = REQUIRED_COLUMNS - set(df.columns)
    if missing:
        raise ImportFileError(f"Missing required columns: {', '.join(sorted(missing))}")
    df = df.dropna(how="all")
    return df.astype(object).where(df.notna(), None)


def _fmt_errors(exc: ValidationError) -> list[str]:
    return [f"{'.'.join(map(str, e['loc'])) or 'row'}: {e['msg']}" for e in exc.errors()]


def _chunks(items: list[dict[str, Any]], size: int) -> Iterable[list[dict[str, Any]]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


class ProductImportService:
    def __init__(self, products: ProductRepository) -> None:
        self.products = products

    async def import_file(self, filename: str, content: bytes, *, dry_run: bool = False) -> ImportReport:
        fmt = detect_format(filename, content[:8])
        df = await asyncio.to_thread(_read_dataframe, content, fmt)

        valid: dict[str, dict[str, Any]] = {}
        errors: list[ImportRowError] = []
        warnings: list[str] = []

        for idx, raw in enumerate(df.to_dict(orient="records")):
            file_row = idx + 2  # +1 заголовок, +1 нумерация с единицы
            try:
                row = ProductImportRow.model_validate(raw)
            except ValidationError as exc:
                errors.append(ImportRowError(row=file_row, sku=raw.get("sku"), errors=_fmt_errors(exc)))
                continue
            if row.sku in valid:
                warnings.append(f"Row {file_row}: duplicate SKU {row.sku}, last occurrence wins")
            if row.retail_price < row.cost_price:
                warnings.append(f"Row {file_row}: SKU {row.sku} is sold below cost")
            data = row.model_dump()
            if "wholesale_price" not in df.columns:
                data.pop("wholesale_price")  # файл без колонки опта не стирает уже заданные оптовые цены
            valid[row.sku] = data

        created = updated = 0
        if not dry_run and valid:
            # Все батчи в одной транзакции запроса: либо весь файл, либо ничего
            for batch in _chunks(list(valid.values()), BATCH_SIZE):
                c, u = await self.products.bulk_upsert(batch)
                created += c
                updated += u

        return ImportReport(
            total_rows=len(df),
            created=created,
            updated=updated,
            failed=len(errors),
            dry_run=dry_run,
            errors=errors[:500],
            warnings=warnings[:500],
        )

    async def export(self, fmt: FileFormat) -> bytes:
        records = [{col: getattr(p, col) for col in EXPORT_COLUMNS} async for p in self.products.stream_all()]
        return await asyncio.to_thread(_write_dataframe, records, fmt)


def _neutralize_formula(v):
    """CSV/Formula injection: «=HYPERLINK(…)» в названии товара Excel выполнил бы как формулу. Экранируем апострофом."""
    if isinstance(v, str) and v[:1] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + v
    return v


def _write_dataframe(records: list[dict[str, Any]], fmt: FileFormat) -> bytes:
    df = pd.DataFrame.from_records(records, columns=EXPORT_COLUMNS)
    # Защита от CSV/Formula injection: ячейка, начинающаяся с = + - @, исполнится в Excel
    for col in ("sku", "name", "description"):
        df[col] = df[col].map(lambda v: f"'{v}" if isinstance(v, str) and v[:1] in "=+-@\t\r" else v)
    buf = io.BytesIO()
    if fmt is FileFormat.XLSX:
        df = df.map(_neutralize_formula)
        df.to_excel(buf, index=False, engine="openpyxl", sheet_name="products")
    else:
        df.map(_neutralize_formula).to_csv(buf, index=False, encoding="utf-8-sig")
    return buf.getvalue()
