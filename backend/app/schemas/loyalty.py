from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models.loyalty import DiscountType


class LoyaltyTierIn(BaseModel):
    name: str = Field(min_length=1, max_length=50)
    min_total_spent: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    discount_type: DiscountType
    discount_value: Decimal = Field(ge=0, max_digits=12, decimal_places=2)
    min_order_for_fixed: Decimal = Field(default=Decimal("0"), ge=0)
    color_hex: str = Field(default="#CD7F32", pattern=r"^#[0-9A-Fa-f]{6}$")
    is_active: bool = True

    @model_validator(mode="after")
    def _percent_cap(self) -> "LoyaltyTierIn":
        if self.discount_type is DiscountType.PERCENT and self.discount_value > 100:
            raise ValueError("Percent discount cannot exceed 100")
        return self


class LoyaltyTierOut(LoyaltyTierIn):
    model_config = ConfigDict(from_attributes=True)
    id: int


class LoyaltyProgress(BaseModel):

    current_tier: LoyaltyTierOut | None
    next_tier: LoyaltyTierOut | None
    total_spent: Decimal
    amount_to_next: Decimal | None
    progress: float = Field(ge=0, le=1)  # 0..1 для LinearProgressIndicator


class CartLine(BaseModel):
    product_id: int
    sku: str
    name: str
    quantity: int
    unit_price: Decimal  # фактическая (оптовая или розничная) с учётом объёма партии
    retail_unit_price: Decimal
    price_source: str
    unit_cost: Decimal = Field(exclude=True)  # себестоимость никогда не уходит клиенту
    discount_amount: Decimal
    line_total: Decimal


class CartQuote(BaseModel):
    lines: list[CartLine]
    subtotal: Decimal
    loyalty_discount: Decimal
    total: Decimal
    tier_name: str | None
    audience: str  # anonymous | b2c | b2b
    price_list_name: str | None = None
    wholesale_savings: Decimal = Decimal("0")  # «Ваша выгода по оптовому прайсу»
