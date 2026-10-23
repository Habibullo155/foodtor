import secrets
from collections.abc import Sequence
from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    DeliveryMethod,
    Order,
    OrderItem,
    OrderStatus,
    OrderStatusHistory,
    PaymentMethod,
    PaymentStatus,
    Product,
    User,
)
from app.services import referrals, shop_info
from app.services.cart import CartService, LineRequest
from app.services.checkout import PromoService
from app.services.geo import get_settings_row
from app.services.loyalty import LoyaltyService


class OrderError(Exception):
    pass


class OrderService:
    def __init__(self, session: AsyncSession, cart: CartService, loyalty: LoyaltyService) -> None:
        self.session = session
        self.cart = cart
        self.loyalty = loyalty

    async def checkout(
        self,
        user: User,
        lines: Sequence[tuple[int, int]],
        *,
        delivery: DeliveryMethod,
        address: str,
        name: str,
        phone: str,
        payment: PaymentMethod,
        note: str | None = None,
        promo_code: str | None = None,
    ) -> Order:
        """
        Корзина хранится на устройстве; сюда приходят только (product_id, qty).
        Всё денежное считается здесь: цены (опт/розница), лояльность, промокод, доставка.
        """
        merged: dict[int, int] = {}
        for product_id, qty in lines:
            merged[product_id] = merged.get(product_id, 0) + qty
        if not merged:
            raise OrderError("Cart is empty")

        # Блокируем товары и списываем остатки атомарно (защита от овер-селла)
        locked = {
            p.id: p
            for p in (
                await self.session.scalars(select(Product).where(Product.id.in_(merged)).with_for_update(of=Product))
            ).unique()
        }
        items: list[LineRequest] = []
        for product_id, qty in merged.items():
            product = locked.get(product_id)
            if product is None or not product.is_active:
                raise OrderError(f"Product {product_id} is not available")
            if product.stock < qty:
                raise OrderError(f"Not enough stock for {product.name}")
            product.stock -= qty
            items.append(LineRequest(product, qty))

        quote = await self.cart.quote(user, items)  # та же цена, что пользователь видел в корзине
        settings = await get_settings_row(self.session)
        if quote.audience == "b2b" and quote.subtotal < settings.wholesale_min_order:
            raise OrderError(f"Минимальный заказ для оптовых клиентов — {settings.wholesale_min_order:.0f} ₽")
        rules = shop_info.from_row(settings).delivery
        if problem := rules.problem(delivery, quote.total):
            raise OrderError(problem)
        promo, promo_discount = await PromoService(self.session).apply(promo_code, quote.total, user)
        fee = rules.fee(delivery, quote.total)
        total = quote.total - promo_discount + fee

        order = Order(
            number=f"{datetime.now(UTC):%y%m%d}-{secrets.token_hex(3).upper()}",
            user_id=user.id,
            subtotal=quote.subtotal,
            loyalty_discount=quote.loyalty_discount,
            promo_code=promo.code if promo else None,
            promo_discount=promo_discount,
            shipping_price=fee,
            total=total,
            cost_total=sum((line.unit_cost * line.quantity for line in quote.lines), Decimal("0")),
            loyalty_tier_name=quote.tier_name,
            customer_segment="b2b" if quote.audience == "b2b" else "b2c",
            price_list_name=quote.price_list_name,
            shipping_address=address,
            customer_name=name,
            customer_phone=phone,
            customer_note=note,
            delivery_method=delivery,
            payment_method=payment,
            payment_status=PaymentStatus.PENDING
            if payment is PaymentMethod.CARD_ONLINE
            else PaymentStatus.NOT_REQUIRED,
            items=[
                OrderItem(
                    product_id=line.product_id,
                    sku=line.sku,
                    name=line.name,
                    quantity=line.quantity,
                    unit_price=line.unit_price,
                    retail_unit_price=line.retail_unit_price,
                    price_source=line.price_source,
                    unit_cost=line.unit_cost,
                    discount_amount=line.discount_amount,
                    line_total=line.line_total,
                )
                for line in quote.lines
            ],
        )
        self.session.add(order)
        await self.session.flush()
        return order

    async def change_status(
        self, order: Order, new_status: OrderStatus, actor: User, comment: str | None = None
    ) -> Order:
        if not order.can_transition_to(new_status):
            raise OrderError(f"Transition {order.status.value} → {new_status.value} is not allowed")

        self.session.add(
            OrderStatusHistory(
                order_id=order.id,
                from_status=order.status,
                to_status=new_status,
                changed_by_id=actor.id,
                comment=comment,
                created_at=datetime.now(UTC),
            )
        )
        if new_status is OrderStatus.PICKING:
            order.picker_id = actor.id
        if new_status is OrderStatus.CANCELLED:
            await self._restock(order)
            await PromoService(self.session).release(order.promo_code)
        order.status = new_status

        if new_status is OrderStatus.DELIVERED:
            order.delivered_at = datetime.now(UTC)
            # Оплата при получении: доставлено = деньги получены курьером
            if order.payment_method is PaymentMethod.CASH and order.payment_status is PaymentStatus.NOT_REQUIRED:
                order.payment_status, order.paid_at = PaymentStatus.PAID, order.delivered_at
            await self.session.flush()  # чтобы SUM в пересчёте увидел новый статус
            # upgraded=True → точка расширения: событие в очередь уведомлений («Вы стали Gold!»)
            _tier, _upgraded = await self.loyalty.recalculate_for_user(order.user_id)
            await referrals.reward_inviter(self.session, order.user_id)
        return order

    async def _restock(self, order: Order) -> None:
        for item in order.items:
            if item.product_id:
                # FOR UPDATE OF products: у товара eager-JOIN на категорию, а Postgres запрещает
                # блокировку «nullable стороны» LEFT JOIN — блокируем только строку товара
                product = await self.session.scalar(
                    select(Product).where(Product.id == item.product_id).with_for_update(of=Product)
                )
                if product:
                    product.stock += item.quantity
