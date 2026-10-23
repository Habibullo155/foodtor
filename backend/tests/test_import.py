import io
from decimal import Decimal

import pandas as pd
import pytest
from PIL import Image
from sqlalchemy import select

from app.models import Product, SystemRole
from app.services import images
from app.services.import_export import FileFormat, ImportFileError, ProductImportService, _write_dataframe
from tests import factories as f
from tests.test_release_flows import staff

CSV = "Артикул;Название;Себестоимость;Цена;Остаток\nA-1;Кружка;100,50;299,90;10\nA-2;;10;20;1\nA-3;Ложка;50;40;5\n"


def _png(size=(400, 400)) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, (200, 30, 30)).save(buf, "PNG")
    return buf.getvalue()


async def test_csv_ru_headers_and_row_errors(db):
    report = await ProductImportService(db).import_file("p.csv", CSV.encode(), dry_run=True)
    assert (report.total_rows, report.created, report.failed) == (3, 2, 1)
    assert report.errors[0].row == 3 and report.errors[0].sku == "A-2"
    assert any("дешевле себестоимости" in w for w in report.warnings)


async def test_rejects_fake_xlsx(db):
    with pytest.raises(ImportFileError):
        await ProductImportService(db).import_file("evil.xlsx", b"not a zip", dry_run=True)


async def test_xlsx_formula_injection_escaped(db):
    data = _write_dataframe([{"Название": "=HYPERLINK(1)", "Цена": 2.0}], FileFormat.XLSX)
    assert pd.read_excel(io.BytesIO(data)).loc[0, "Название"].startswith("'=")
    report = await ProductImportService(db).import_file("p.xlsx", data, dry_run=True)
    assert report.failed == 0


async def test_export_edit_import_updates_prices_by_name_and_unit(client, db, monkeypatch):
    veg = await f.category(db, "Овощи")
    tomato = await f.product(db, "Томаты", "200", cat=veg, cost="120")
    tomato.unit = "1 кг"
    tomato.images = []
    cherry = await f.product(db, "Томаты", "350", cat=veg, cost="200")
    cherry.unit = "500 г"
    await db.commit()
    owner = await staff(client, db, SystemRole.OWNER, "owner-imp@test.ru")

    exported = await client.get("/api/v1/admin/products/export", params={"format": "xlsx"}, headers=owner)
    df = pd.read_excel(io.BytesIO(exported.content), dtype=str)
    assert list(df.columns)[:4] == ["Артикул", "Название", "Фасовка", "Категория"] and "Фото" in df.columns

    # без артикулов: товар находится по названию + фасовке, новый не создаётся
    df = df.drop(columns=["Артикул"])
    df.loc[df["Фасовка"] == "1 кг", ["Себестоимость", "Цена", "Оптовая цена"]] = ["130", "220", "190"]
    downloads: list[str] = []

    async def fake_download(url: str) -> bytes:
        downloads.append(url)
        return _png()

    monkeypatch.setattr(images, "download", fake_download)
    df.loc[df["Фасовка"] == "500 г", "Фото"] = "https://cdn.example.com/cherry.png"
    new_row = {"Название": "Огурцы", "Фасовка": "1 кг", "Категория": "Овощи", "Себестоимость": "60", "Цена": "110"}
    df = pd.concat([df, pd.DataFrame([new_row])], ignore_index=True)
    buf = io.BytesIO()
    df.to_excel(buf, index=False)

    r = await client.post(
        "/api/v1/admin/products/import",
        headers=owner,
        files={"file": ("prices.xlsx", buf.getvalue(), "application/octet-stream")},
    )
    report = r.json()
    assert (report["created"], report["updated"], report["images_downloaded"], report["failed"]) == (1, 2, 1, 0)
    assert downloads == ["https://cdn.example.com/cherry.png"]

    db.expire_all()
    rows = {(p.name, p.unit): p for p in (await db.scalars(select(Product))).unique().all()}
    assert len(rows) == 3
    kg = rows[("Томаты", "1 кг")]
    assert (kg.cost_price, kg.retail_price, kg.wholesale_price) == (Decimal("130.00"), Decimal("220.00"), Decimal("190.00"))
    assert rows[("Томаты", "500 г")].images[0].url.startswith("/media/products/")
    assert rows[("Огурцы", "1 кг")].category.name == "Овощи"


async def test_own_photo_links_are_left_alone(db, monkeypatch):
    async def boom(url: str) -> bytes:
        raise AssertionError(f"не должно скачиваться: {url}")

    monkeypatch.setattr(images, "download", boom)
    tomato = await f.product(db, "Томаты", "200")
    tomato.unit = "1 кг"
    await db.commit()
    csv = "Название;Фасовка;Цена;Фото\nТоматы;1 кг;210;/static/demo/tomato.webp\n"
    report = await ProductImportService(db).import_file("p.csv", csv.encode())
    assert (report.updated, report.images_downloaded, report.warnings) == (1, 0, [])


def test_download_refuses_internal_addresses():
    for url in ("http://127.0.0.1/x.png", "http://localhost/x.png", "file:///etc/passwd", "ftp://x.ru/a.png"):
        with pytest.raises(images.ImageError):
            import asyncio

            asyncio.run(images.download(url))
