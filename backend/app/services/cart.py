from collections.abc import Sequence
from dataclasses import dataclass
from decimal import Decimal

from app.models import CartItem, Product, User
from app.schemas.loyalty import CartLine, CartQuote
from app.services.loyalty import allocate_discount, calculate_discount, money
from app.services.pricing import PricingService


@dataclass(frozen=True, slots=True)
class LineRequest:
    """Позиция корзины без хранения в БД (корзина живёт на устройстве клиента)."""

    product: Product
    quantity: int

    @property
    def product_id(self) -> int:
        return self.product.id


class CartService:
    def __init__(self, pricing: PricingService) -> None:
        self.pricing = pricing

    async def quote(self, user: User, items: Sequence[CartItem | LineRequest]) -> CartQuote:
        """
        1. Цена единицы — от PricingService с учётом количества (лестница оптовых цен).
        2. Скидка уровня лояльности — только для розницы: у B2B уже договорные цены,
           двойная скидка уводила бы заказы в минус по марже.
        Цены всегда из БД — клиентским ценам не доверяем.
        """
        ctx, prices = await self.pricing.price_many(
            user, [i.product for i in items], {i.product_id: i.quantity for i in items}
        )
        line_amounts = [prices[i.product_id].unit_price * i.quantity for i in items]
        subtotal = money(sum(line_amounts, Decimal("0")))

        tier = None if ctx.is_wholesale else user.loyalty_tier
        if tier is not None and not tier.is_active:
            tier = None
        discount = calculate_discount(subtotal, tier)
        shares = allocate_discount(line_amounts, discount)

        lines = [
            CartLine(
                product_id=item.product_id,
                sku=item.product.sku,
                name=item.product.name,
                quantity=item.quantity,
                unit_price=prices[item.product_id].unit_price,
                retail_unit_price=prices[item.product_id].retail_price,
                price_source=prices[item.product_id].source.value,
                unit_cost=item.product.cost_price,
                discount_amount=share,
                line_total=money(amount - share),
            )
            for item, amount, share in zip(items, line_amounts, shares, strict=True)
        ]
        retail_total = sum((ln.retail_unit_price * ln.quantity for ln in lines), Decimal("0"))
        return CartQuote(
            lines=lines,
            subtotal=subtotal,
            loyalty_discount=discount,
            total=subtotal - discount,
            tier_name=tier.name if tier else None,
            audience=ctx.audience.value,
            price_list_name=ctx.rules.price_list_name if ctx.is_wholesale and ctx.rules else None,
            wholesale_savings=money(retail_total - subtotal) if ctx.is_wholesale else Decimal("0"),
        )
