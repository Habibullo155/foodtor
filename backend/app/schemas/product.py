from decimal import Decimal
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

Sku = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=64, pattern=r"^[A-Za-z0-9._\-]+$")
]
Price = Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=2)]


class ProductImportRow(BaseModel):
    """Строгая валидация одной строки файла импорта. Лишние колонки игнорируются."""

    model_config = ConfigDict(extra="ignore", str_strip_whitespace=True)

    sku: Sku
    name: Annotated[str, StringConstraints(min_length=1, max_length=255)]
    description: Annotated[str, StringConstraints(max_length=10_000)] = ""
    cost_price: Price
    retail_price: Price
    compare_at_price: Price | None = None
    wholesale_price: Price | None = None
    stock: Annotated[int, Field(ge=0, le=1_000_000)] = 0
    is_active: bool = True
    category_id: int | None = None

    @field_validator("description", mode="before")
    @classmethod
    def _none_to_empty(cls, v: object) -> object:
        return "" if v is None else v

    @field_validator("cost_price", "retail_price", "compare_at_price", "wholesale_price", mode="before")
    @classmethod
    def _normalize_decimal(cls, v: object) -> object:
        # Excel из RU-локали отдаёт «1 299,90» — нормализуем
        if isinstance(v, str):
            v = v.replace(" ", "").replace(" ", "").replace(",", ".")
        if isinstance(v, float):
            v = Decimal(str(v)).quantize(Decimal("0.01"))
        return v

    @model_validator(mode="after")
    def _check_prices(self) -> "ProductImportRow":
        # retail < cost — не ошибка (распродажа), сервис импорта выдаст предупреждение
        if self.compare_at_price is not None and self.compare_at_price < self.retail_price:
            raise ValueError("compare_at_price must be >= retail_price")
        return self


class ImportRowError(BaseModel):
    row: int  # номер строки в файле (с учётом заголовка) — удобно для пользователя
    sku: str | None
    errors: list[str]


class ImportReport(BaseModel):
    total_rows: int
    created: int
    updated: int
    failed: int
    dry_run: bool
    errors: list[ImportRowError]
    warnings: list[str]
