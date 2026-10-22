from datetime import UTC, datetime
from decimal import Decimal as D

from app.models import (
    Category,
    Order,
    OrderItem,
    OrderStatus,
    Product,
    ProductImage,
    ProductRelation,
    RelationKind,
    Role,
    User,
)

_seq = iter(range(1, 10_000))


async def category(s, name="Овощи") -> Category:
    c = Category(name=name, slug=f"{name}-{next(_seq)}")
    s.add(c)
    await s.flush()
    return c


async def product(s, name, price="100", *, cat=None, stock=10, active=True, cost=None) -> Product:
    p = Product(
        sku=f"SKU-{next(_seq)}",
        name=name,
        description="",
        retail_price=D(price),
        cost_price=D(cost or str(D(price) * D("0.6"))),
        stock=stock,
        is_active=active,
        category_id=cat.id if cat else None,
    )
    p.images = [ProductImage(url=f"https://cdn/{name}.png", position=0)]
    s.add(p)
    await s.flush()
    return p


async def customer(s, email=None) -> User:
    role = Role(code=f"customer-{next(_seq)}", title="Покупатель", is_staff=False)
    s.add(role)
    await s.flush()
    u = User(email=email or f"u{next(_seq)}@test.ru", password_hash="x", full_name="Тест", role_id=role.id)
    s.add(u)
    await s.flush()
    return u


async def delivered_order(s, user, *products) -> Order:
    total = sum((p.retail_price for p in products), D("0"))
    o = Order(
        number=f"T-{next(_seq)}",
        user_id=user.id,
        status=OrderStatus.DELIVERED,
        subtotal=total,
        total=total,
        cost_total=sum((p.cost_price for p in products), D("0")),
        shipping_address="Москва",
        delivered_at=datetime.now(UTC),
        items=[
            OrderItem(
                product_id=p.id,
                sku=p.sku,
                name=p.name,
                quantity=1,
                unit_price=p.retail_price,
                retail_unit_price=p.retail_price,
                unit_cost=p.cost_price,
                line_total=p.retail_price,
            )
            for p in products
        ],
    )
    s.add(o)
    await s.flush()
    return o


async def relate(s, source, target, kind=RelationKind.CROSS_SELL, position=0):
    s.add(ProductRelation(source_id=source.id, target_id=target.id, kind=kind, position=position))
    await s.flush()
