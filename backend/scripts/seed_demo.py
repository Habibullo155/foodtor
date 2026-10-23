"""
Демо-данные для показа и локальной разработки: каталог (71 товар с фото), отзывы, покупательница
с историей заказов, сотрудники (владелец, менеджер, сборщик, курьер), уровни лояльности, зона доставки.

    DEMO_OWNER_PASSWORD=... DEMO_MANAGER_PASSWORD=... DEMO_PICKER_PASSWORD=... DEMO_COURIER_PASSWORD=... \
        python -m scripts.seed_demo

Пароли сотрудников НЕ захардкожены: берутся из окружения (значения — в DEMO_ACCOUNTS.md, его читает scripts/demo.sh).
Покупательница входит по SMS: номер +7 916 123-45-67, код показывается на экране (SMS_PROVIDER=console).
Оптовик с подключённым прайсом — +7 916 111-22-33, заявка на проверке — +7 916 222-33-44.
Скрипт идемпотентен: повторный запуск ничего не дублирует. В релизе не используется (там scripts.create_owner).
"""

import asyncio
import json
import os
import random
import sys
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path

from sqlalchemy import func, select

from app.core.security import hash_password
from app.db.session import SessionFactory
from app.models import (
    AccountType,
    B2BAccount,
    B2BStatus,
    Banner,
    Category,
    DeliveryMethod,
    LoyaltyTier,
    OrderStatus,
    PaymentMethod,
    Product,
    ProductImage,
    Review,
    ReviewStatus,
    Story,
    StorySlide,
    SystemRole,
    User,
)
from app.models.loyalty import DiscountType
from app.repositories.loyalty import LoyaltyTierRepository, UserRepository
from app.services.bootstrap import ensure_system_roles
from app.services.cart import CartService
from app.services.geo import get_settings_row
from app.services.loyalty import LoyaltyService
from app.services.orders import OrderService
from app.services.pricing import PricingRepository, PricingService
from app.web.catalog import slugify

DATA = json.loads((Path(__file__).resolve().parents[1] / "app" / "demo" / "catalog.json").read_text())
IMG = "/static/demo/{}"

STAFF = [
    ("owner@saasshop.local", "Хабиб Зухуров", SystemRole.OWNER, "DEMO_OWNER_PASSWORD"),
    ("manager@saasshop.local", "Анна Смирнова", SystemRole.MANAGER, "DEMO_MANAGER_PASSWORD"),
    ("picker@saasshop.local", "Игорь Петров", SystemRole.PICKER, "DEMO_PICKER_PASSWORD"),
    ("courier@saasshop.local", "Руслан Алиев", SystemRole.COURIER, "DEMO_COURIER_PASSWORD"),
]
CUSTOMER_PHONE = "+79161234567"
REVIEWERS = ["Ольга Соколова", "Дмитрий Попов", "Елена Новикова", "Сергей Морозов", "Наталья Волкова", "Андрей Лебедев"]
REVIEW_TEXTS = {
    5: [
        "Отличное качество, свежее — возьму ещё!",
        "Привезли быстро, всё целое. Спасибо!",
        "Лучшее, что пробовала у вас.",
    ],
    4: ["Хорошо, но упаковка могла быть получше.", "Вкусно, чуть дороже, чем ожидал."],
    3: ["Нормально, ничего особенного."],
}
COST_RATIO = {1: 0.62, 2: 0.65, 3: 0.6, 4: 0.5, 5: 0.7, 6: 0.68, 7: 0.72, 8: 0.45, 9: 0.68, 10: 0.55, 11: 0.6, 12: 0.75}


def describe(p: dict, category: str) -> str:
    return (
        f"{p['name']} ({p['unit']}) от {p['brand']}, {p['country']}. Отбираем каждое утро и привозим в день заказа. "
        f"Раздел «{category}» — свежие продукты с доставкой за 2 часа."
    )


async def seed_staff(session, roles) -> dict[str, User]:
    staff = {}
    for email, name, role, env in STAFF:
        user = await session.scalar(select(User).where(User.email == email))
        if user is None:
            user = User(email=email, full_name=name, role_id=roles[role].id, password_hash="")
            session.add(user)
        user.password_hash = hash_password(os.environ[env])
        user.role_id, user.is_active = roles[role].id, True
        staff[role.value] = user
    await session.flush()
    return staff


async def seed_catalog(session) -> list[Product]:
    if await session.scalar(select(func.count()).select_from(Product)):
        return list((await session.scalars(select(Product))).unique().all())
    cats = {}
    for pos, c in enumerate(DATA["categories"]):
        cat = Category(name=c["name"], slug=slugify(c["name"]), image_url=IMG.format(c["image"]), position=pos)
        session.add(cat)
        cats[c["id"]] = cat
    await session.flush()
    products = []
    created = datetime.now(UTC) - timedelta(days=60)
    for p in DATA["products"]:
        cat = cats[p["category_id"]]
        price = Decimal(str(p["price"]))
        prod = Product(
            sku=f"GR-{p['id']:04d}",
            name=p["name"],
            description=describe(p, cat.name),
            brand=p["brand"],
            unit=p["unit"],
            retail_price=price,
            cost_price=(price * Decimal(str(COST_RATIO.get(p["category_id"], 0.65)))).quantize(Decimal("1")),
            compare_at_price=Decimal(str(p["old_price"])) if p["old_price"] else None,
            stock=p["stock"],
            is_hit=p["hit"],
            category_id=cat.id,
            attributes={"Страна": p["country"]},
            images=[ProductImage(url=IMG.format(p["image"]), position=0)],
        )
        prod.created_at = datetime.now(UTC) if p["new"] else created
        session.add(prod)
        products.append(prod)
    await session.flush()
    return products


async def seed_people(session, roles, products, staff):
    if await session.scalar(select(User).where(User.phone_e164 == CUSTOMER_PHONE)):
        return
    rnd = random.Random(7)  # noqa: S311 — детерминированные демо-данные, не криптография
    maria = User(
        full_name="Мария Кузнецова",
        phone=CUSTOMER_PHONE,
        phone_e164=CUSTOMER_PHONE,
        phone_verified_at=datetime.now(UTC),
        password_hash=hash_password(os.urandom(16).hex()),
        role_id=roles[SystemRole.CUSTOMER].id,
    )
    session.add(maria)
    reviewers = []
    for i, name in enumerate(REVIEWERS):
        u = User(
            full_name=name,
            email=f"buyer{i}@demo.local",
            password_hash=hash_password(os.urandom(16).hex()),
            role_id=roles[SystemRole.CUSTOMER].id,
        )
        session.add(u)
        reviewers.append(u)
    await session.flush()

    # Отзывы: у популярных товаров — по нескольку, часть ждёт модерации (видно в админке)
    for p in products[:40]:
        for u in rnd.sample(reviewers, rnd.randint(1, 4)):
            rating = rnd.choice([5, 5, 5, 4, 4, 3])
            session.add(
                Review(
                    product_id=p.id,
                    user_id=u.id,
                    rating=rating,
                    text=rnd.choice(REVIEW_TEXTS[rating]),
                    status=ReviewStatus.APPROVED if rnd.random() < 0.85 else ReviewStatus.PENDING,
                )
            )

    # История заказов Марии (доставленные — для «Истории покупок», рекомендаций и лояльности) + один в пути
    pricing = PricingService(PricingRepository(session))
    orders = OrderService(
        session, CartService(pricing), LoyaltyService(UserRepository(session), LoyaltyTierRepository(session))
    )
    owner, courier = staff["owner"], staff["courier"]
    plan = [
        (OrderStatus.DELIVERED, 28),
        (OrderStatus.DELIVERED, 14),
        (OrderStatus.DELIVERED, 6),
        (OrderStatus.SHIPPED, 0),
    ]
    for status, days in plan:
        lines = [(p.id, rnd.randint(1, 3)) for p in rnd.sample(products, 4)]
        o = await orders.checkout(
            maria,
            lines,
            delivery=DeliveryMethod.COURIER,
            address="Москва, ул. Тверская, 12, кв. 45",
            name="Мария",
            phone="+7 916 123-45-67",
            payment=PaymentMethod.CASH,
        )
        o.dest_lat, o.dest_lng = 55.7637, 37.6065
        for s in (OrderStatus.PICKING, OrderStatus.SHIPPED, OrderStatus.DELIVERED):
            if list(OrderStatus).index(s) <= list(OrderStatus).index(status):
                await orders.change_status(o, s, owner, None)
        if status is OrderStatus.SHIPPED:
            o.courier_id = courier.id
        o.created_at = datetime.now(UTC) - timedelta(days=days, hours=3)
    await session.flush()


def _cat(cid: int) -> str:
    name = next(c["name"] for c in DATA["categories"] if c["id"] == cid)
    return f"/catalog/{slugify(name)}"


STORIES = [  # (подпись, цвет, обложка, [(картинка, заголовок, подпись, кнопка, ссылка)])
    (
        "Сезон ягод",
        "#E11D48",
        "strawberries",
        [
            ("strawberries", "Клубника −20%", "Собрана вчера, у вас — сегодня", "Смотреть ягоды", _cat(3)),
            ("blueberries", "Голубика из Марокко", "Новый урожай", None, None),
        ],
    ),
    (
        "Фермерское",
        "#16A34A",
        "carrots",
        [("carrots", "Овощи от фермы Иванова", "Без посредников, прямо с грядки", "К овощам", _cat(1))],
    ),
    (
        "Рецепт дня",
        "#D97706",
        "spaghetti",
        [
            ("spaghetti", "Паста помодоро за 15 минут", None, None, None),
            ("plum_tomatoes", "Сливовидные томаты", "+ чеснок", None, None),
            ("basil", "Финальный штрих — базилик", None, "Собрать корзину", _cat(6)),
        ],
    ),
    ("Для вас", "#4CAF50", "avocado", [("avocado", "Промокод FRESH300", "−300 ₽ от 1500 ₽", None, None)]),
    ("За 2 часа", "#0891B2", "lemon", [("lemon", "Экспресс-доставка за 2 часа", "Свежее — значит быстро", None, None)]),
    ("Бакалея", "#CA8A04", "quinoa", [("quinoa", "Киноа, нут, кускус", "Новинки на полке круп", "К крупам", _cat(5))]),
    (
        "Бизнесу",
        "#0B5D3B",
        "potatoes",
        [("potatoes", "Опт для кафе и магазинов", "Оптовые цены по вашему прайсу", "Оставить заявку", "/business")],
    ),
]


async def seed_banners(session):
    if await session.scalar(select(func.count()).select_from(Banner)):
        return
    session.add_all(
        [
            Banner(
                title="Неделя ягод",
                text="Клубника и голубика со скидкой до 20% — собраны вчера, у вас сегодня",
                image_url=IMG.format("strawberries.webp"),
                button_label="Смотреть акции",
                link_url="/promo",
                theme="green",
                button_color="orange",
                position=0,
            ),
            Banner(
                title="Приведите друга — получите 300 ₽",
                text="Другу — 300 ₽ на первый заказ",
                image_url=IMG.format("avocado.webp"),
                button_label="Пригласить",
                link_url="/friends",
                theme="orange",
                button_color="white",
                position=1,
            ),
        ]
    )


async def seed_stories(session):
    if await session.scalar(select(func.count()).select_from(Story)):
        return
    for pos, (title, color, cover, slides) in enumerate(STORIES):
        session.add(
            Story(
                title=title,
                color_hex=color,
                cover_url=IMG.format(cover + ".webp"),
                position=pos,
                slides=[
                    StorySlide(
                        position=i, image_url=IMG.format(img + ".webp"), headline=h, caption=c, cta_label=cl, cta_url=cu
                    )
                    for i, (img, h, c, cl, cu) in enumerate(slides)
                ],
            )
        )


async def seed_tiers(session):
    if await session.scalar(select(func.count()).select_from(LoyaltyTier)):
        return
    for name, spent, pct, color in [
        ("Bronze", 0, 0, "#B45309"),
        ("Silver", 10000, 3, "#64748B"),
        ("Gold", 30000, 5, "#CA8A04"),
        ("Platinum", 75000, 8, "#4F46E5"),
    ]:
        session.add(
            LoyaltyTier(
                name=name,
                min_total_spent=Decimal(spent),
                discount_type=DiscountType.PERCENT,
                discount_value=Decimal(pct),
                color_hex=color,
            )
        )


async def seed_b2b(session, roles, products):
    if await session.scalar(select(func.count()).select_from(B2BAccount)):
        return
    for p in products:
        p.wholesale_price = (p.retail_price * Decimal("0.85")).quantize(Decimal("1"))
    companies = [
        ("ООО «Зелёная ложка»", "7704123450", B2BStatus.APPROVED, "Алексей Кравцов", "+79161112233"),
        ("ИП Соколова Е. А.", "771234567859", B2BStatus.PENDING, "Елена Соколова", "+79162223344"),
    ]
    for legal, inn, status, name, phone in companies:
        acc = B2BAccount(legal_name=legal, tax_id=inn, status=status)
        if status is B2BStatus.APPROVED:
            acc.verified_at = datetime.now(UTC)
        session.add(
            User(
                full_name=name,
                phone=phone,
                phone_e164=phone,
                phone_verified_at=datetime.now(UTC),
                password_hash=hash_password(os.urandom(16).hex()),
                role_id=roles[SystemRole.CUSTOMER].id,
                account_type=AccountType.B2B,
                b2b_account=acc,
            )
        )
    await session.flush()


async def main() -> None:
    missing = [env for *_, env in STAFF if not os.getenv(env)]
    if missing:
        sys.exit(f"Set env vars: {', '.join(missing)} (значения — в DEMO_ACCOUNTS.md)")
    async with SessionFactory() as session, session.begin():
        roles = await ensure_system_roles(session)
        staff = await seed_staff(session, roles)
        await seed_tiers(session)
        await seed_stories(session)
        await seed_banners(session)
        products = await seed_catalog(session)
        zone = await get_settings_row(session)
        zone.delivery_cities = ["Москва"]
        await seed_people(session, roles, products, staff)
        await seed_b2b(session, roles, products)
    print(
        f"Демо готово: {len(products)} товаров, сотрудники: {', '.join(e for e, *_ in STAFF)}, "
        f"покупательница — вход по SMS {CUSTOMER_PHONE}"
    )


if __name__ == "__main__":
    asyncio.run(main())
