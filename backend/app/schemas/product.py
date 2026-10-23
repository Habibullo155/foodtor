from decimal import Decimal
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

Sku = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=64, pattern=r"^[A-Za-z0-9._\-]+$")
]
Price = Annotated[Decimal, Field(ge=0, max_digits=12, decimal_places=2)]


Text = Annotated[str, StringConstraints(max_length=255)]
YES = {"да", "yes", "true", "1", "+", "в продаже"}
NO = {"нет", "no", "false", "0", "-", "снят"}


class ProductImportRow(BaseModel):
    """Строгая валидация одной строки файла импорта. Лишние колонки игнорируются, пустые ячейки — «не менять»."""

    model_config = ConfigDict(extra="ignore", str_strip_whitespace=True)

    sku: Sku | None = None
    name: Annotated[str, StringConstraints(min_length=1, max_length=255)]
    unit: Annotated[str, StringConstraints(max_length=32)] | None = None
    brand: Annotated[str, StringConstraints(max_length=120)] | None = None
    category: Text | None = None
    description: Annotated[str, StringConstraints(max_length=10_000)] | None = None
    cost_price: Price | None = None
    retail_price: Price
    compare_at_price: Price | None = None
    wholesale_price: Price | None = None
    stock: Annotated[int, Field(ge=0, le=1_000_000)] | None = None
    is_active: bool | None = None
    image_url: Annotated[str, StringConstraints(max_length=1024)] | None = None

    @field_validator("sku", "unit", "brand", "category", "description", "image_url", mode="before")
    @classmethod
    def _blank_to_none(cls, v: object) -> object:
        return None if isinstance(v, str) and not v.strip() else v

    @field_validator("cost_price", "retail_price", "compare_at_price", "wholesale_price", mode="before")
    @classmethod
    def _normalize_decimal(cls, v: object) -> object:
        # Excel из RU-локали отдаёт «1 299,90 ₽» — нормализуем
        if isinstance(v, str):
            v = v.replace(" ", "").replace(" ", "").replace("₽", "").replace(",", ".")
            return v or None
        if isinstance(v, float):
            v = Decimal(str(v)).quantize(Decimal("0.01"))
        return v

    @field_validator("stock", mode="before")
    @classmethod
    def _int(cls, v: object) -> object:
        if isinstance(v, str):
            v = v.replace(" ", "").replace(",", ".")
            return int(float(v)) if v else None
        return v

    @field_validator("is_active", mode="before")
    @classmethod
    def _bool(cls, v: object) -> object:
        if isinstance(v, str):
            low = v.strip().lower()
            if low in YES:
                return True
            if low in NO:
                return False
            return None if not low else v
        return v

    @model_validator(mode="after")
    def _check_prices(self) -> "ProductImportRow":
        # retail < cost — не ошибка (распродажа), сервис импорта выдаст предупреждение
        if self.compare_at_price is not None and self.compare_at_price < self.retail_price:
            raise ValueError("«Старая цена» должна быть больше обычной")
        if self.wholesale_price is not None and self.wholesale_price > self.retail_price:
            raise ValueError("Оптовая цена выше розничной")
        return self


class CategoryImportRow(BaseModel):
    """Строка листа «Категории»: видимость на сайте, порядок и фото."""

    model_config = ConfigDict(extra="ignore", str_strip_whitespace=True)

    name: Annotated[str, StringConstraints(min_length=1, max_length=120)]
    is_visible: bool | None = None
    position: Annotated[int, Field(ge=0, le=10_000)] | None = None
    image_url: Annotated[str, StringConstraints(max_length=1024)] | None = None

    @field_validator("image_url", mode="before")
    @classmethod
    def _blank_to_none(cls, v: object) -> object:
        return ProductImportRow._blank_to_none(v)

    @field_validator("is_visible", mode="before")
    @classmethod
    def _bool(cls, v: object) -> object:
        return ProductImportRow._bool(v)

    @field_validator("position", mode="before")
    @classmethod
    def _int(cls, v: object) -> object:
        return ProductImportRow._int(v)


class ImportRowError(BaseModel):
    row: int  # номер строки в файле (с учётом заголовка) — удобно для пользователя
    sku: str | None
    name: str | None = None
    errors: list[str]


class ImportReport(BaseModel):
    total_rows: int
    created: int
    updated: int
    images_downloaded: int = 0
    categories_updated: int = 0
    failed: int
    dry_run: bool
    errors: list[ImportRowError]
    warnings: list[str]
