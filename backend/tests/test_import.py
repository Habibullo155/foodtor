import io

import pandas as pd
import pytest

from app.services.import_export import FileFormat, ImportFileError, ProductImportService, _write_dataframe

CSV = "Артикул;Название;Себестоимость;Цена;Остаток\nA-1;Кружка;100,50;299,90;10\nA-2;;10;20;1\nA-3;Ложка;50;40;5\n"


@pytest.fixture
def service():
    return ProductImportService(products=None)  # dry_run не трогает репозиторий


async def test_csv_ru_headers_and_row_errors(service):
    report = await service.import_file("p.csv", CSV.encode(), dry_run=True)
    assert (report.total_rows, report.failed) == (3, 1)
    assert report.errors[0].row == 3 and report.errors[0].sku == "A-2"
    assert any("below cost" in w for w in report.warnings)


async def test_rejects_fake_xlsx(service):
    with pytest.raises(ImportFileError):
        await service.import_file("evil.xlsx", b"not a zip", dry_run=True)


async def test_xlsx_roundtrip_and_formula_injection_escaped(service):
    data = _write_dataframe(
        [
            {
                "sku": "X1",
                "name": "=HYPERLINK(1)",
                "description": "",
                "cost_price": 1,
                "retail_price": 2,
                "compare_at_price": None,
                "stock": 0,
                "is_active": True,
                "category_id": None,
            }
        ],
        FileFormat.XLSX,
    )
    assert pd.read_excel(io.BytesIO(data)).loc[0, "name"].startswith("'=")
    report = await service.import_file("p.xlsx", data, dry_run=True)
    assert report.failed == 0
