from decimal import Decimal as D
from urllib.parse import parse_qs

import httpx
import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.core.security import hash_password
from app.models import Order, PaymentStatus, Product, PromoCode, SystemRole, User
from app.services import payments
from app.services.bootstrap import ensure_system_roles
from tests import factories as f

PW = "Secret-pass-123"


async def stock(db, product) -> int:
    return await db.scalar(select(Product.stock).where(Product.id == product.id))


async def register(client, email="buyer@test.ru"):
    r = await client.post(
        "/api/v1/auth/register", json={"email": email, "password": PW, "full_name": "Мария Кузнецова"}
    )
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


async def staff(client, db, role: SystemRole, email: str):
    roles = await ensure_system_roles(db)
    db.add(User(email=email, full_name=role.value.title(), password_hash=hash_password(PW), role_id=roles[role].id))
    await db.commit()
    r = await client.post("/api/v1/auth/login", data={"username": email, "password": PW})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


async def shop(db):
    veg = await f.category(db, "Овощи")
    tomato = await f.product(db, "Томаты", "249", cat=veg, stock=10)
    dill = await f.product(db, "Укроп", "59", cat=veg, stock=3)
    await db.commit()
    return tomato, dill


def checkout_body(*lines, payment="cash", delivery="courier", promo=None):
    return {
        "items": [{"product_id": p.id, "quantity": q} for p, q in lines],
        "delivery": delivery,
        "address": "Москва, ул. Тверская, 1",
        "name": "Мария",
        "phone": "+7 900 000-00-00",
        "payment": payment,
        "promo_code": promo,
    }


async def test_register_me_and_duplicate(client):
    h = await register(client)
    me = (await client.get("/api/v1/auth/me", headers=h)).json()
    assert (me["role"], me["is_staff"], me["permissions"]) == ("customer", False, [])
    dup = await client.post(
        "/api/v1/auth/register", json={"email": "BUYER@test.ru", "password": PW, "full_name": "X Y"}
    )
    assert dup.status_code == 409
    weak = await client.post(
        "/api/v1/auth/register", json={"email": "w@test.ru", "password": "12345678", "full_name": "X Y"}
    )
    assert weak.status_code == 422


async def test_catalog_list_filters_and_badges(client, db):
    tomato, dill = await shop(db)
    body = (await client.get("/api/v1/products", params={"q": "том"})).json()
    assert body["total"] == 1 and body["items"][0]["name"] == "Томаты"
    low = (await client.get("/api/v1/products", params={"q": "укроп"})).json()["items"][0]
    assert "lowStock" in low["badges"] and low["stock_left"] == 3 and "fresh" in low["badges"]
    cats = (await client.get("/api/v1/categories")).json()
    assert cats[0]["name"] == "Овощи" and cats[0]["products_count"] == 2
    # SQL-инъекция в поиске — просто строка, не ломает запрос
    assert (await client.get("/api/v1/products", params={"q": "'; DROP TABLE products; --"})).json()["total"] == 0


async def test_cash_checkout_stock_delivery_and_promo(client, db):
    tomato, dill = await shop(db)
    db.add(PromoCode(code="FRESH300", amount=D("300"), min_order=D("1500"), usage_limit=1))
    await db.commit()
    h = await register(client)

    q = (
        await client.post(
            "/api/v1/me/orders/quote",
            headers=h,
            json={"items": [{"product_id": tomato.id, "quantity": 2}], "promo_code": "fresh300"},
        )
    ).json()
    assert (
        q["promo_error"] == "Промокод действует от 1500 ₽" and q["delivery_fee"] == "199.00" and q["total"] == "697.00"
    )

    r = await client.post("/api/v1/me/orders", headers=h, json=checkout_body((tomato, 7), promo="FRESH300"))
    assert r.status_code == 201, r.text
    order = r.json()
    assert (order["total"], order["delivery_fee"], order["payment_status"]) == (
        "1443.00",
        "0.00",
        "not_required",
    )  # 1743−300
    assert await stock(db, tomato) == 3

    # Лимит промокода исчерпан, остатков не хватает — заказ не создаётся, остатки не трогаются
    assert (
        await client.post("/api/v1/me/orders", headers=h, json=checkout_body((tomato, 7), promo="FRESH300"))
    ).status_code == 409
    assert (await client.post("/api/v1/me/orders", headers=h, json=checkout_body((dill, 4)))).status_code == 409
    assert await stock(db, dill) == 3
    assert len((await client.get("/api/v1/me/orders", headers=h)).json()) == 1


@pytest.fixture
def alfa(monkeypatch):
    """Имитация шлюза Альфа-Банка: register.do / getOrderStatusExtended.do."""
    s = get_settings()
    monkeypatch.setattr(s, "alfa_username", "shop-api")
    monkeypatch.setattr(s, "alfa_password", type(s.jwt_secret)("pw"))
    bank = {"status": 0, "amount": None, "registered": []}

    def handler(request: httpx.Request):
        form = {k: v[0] for k, v in parse_qs(request.content.decode()).items()}
        assert form["userName"] == "shop-api" and form["password"] == "pw"
        if request.url.path.endswith("register.do"):
            bank["registered"].append(form)
            bank["amount"] = bank["amount"] or int(form["amount"])
            return httpx.Response(
                200, json={"orderId": f"bank-{len(bank['registered'])}", "formUrl": "https://pay.test/form"}
            )
        return httpx.Response(200, json={"orderStatus": bank["status"], "amount": bank["amount"]})

    monkeypatch.setattr(payments, "TEST_TRANSPORT", httpx.MockTransport(handler))
    return bank


async def test_online_payment_flow_and_picking_gate(client, db, alfa):
    tomato, _ = await shop(db)
    h = await register(client)
    picker = await staff(client, db, SystemRole.PICKER, "picker@test.ru")

    r = await client.post("/api/v1/me/orders", headers=h, json=checkout_body((tomato, 2), payment="card_online"))
    assert r.status_code == 201, r.text
    order = r.json()
    assert order["pay_url"] == "https://pay.test/form" and order["payment_status"] == "pending"
    assert alfa["registered"][0]["amount"] == str((249 * 2 + 199) * 100)  # копейки

    # Не оплачен → в сборке его нет, взять в работу нельзя
    assert (await client.get("/api/v1/staff/picking", headers=picker)).json() == []
    assert (
        await client.patch(f"/api/v1/staff/orders/{order['id']}/status", headers=picker, json={"status": "picking"})
    ).status_code == 409

    # Поддельный редирект с «успехом» ничего не меняет: банк говорит «не оплачен»
    r = await client.get(
        "/api/v1/payments/alfa/return", params={"orderId": "bank-1", "status": "success"}, follow_redirects=False
    )
    assert "result=fail" in r.headers["location"]

    alfa["status"] = 2  # банк подтвердил оплату → callback
    assert (await client.get("/api/v1/payments/alfa/callback", params={"mdOrder": "bank-1"})).text == "OK"
    queue = (await client.get("/api/v1/staff/picking", headers=picker)).json()
    assert [o["number"] for o in queue] == [order["number"]]
    assert "price" not in str(queue)  # сборщик не видит цен


async def test_payment_amount_mismatch_is_rejected(client, db, alfa):
    tomato, _ = await shop(db)
    h = await register(client)
    order = (
        await client.post("/api/v1/me/orders", headers=h, json=checkout_body((tomato, 1), payment="card_online"))
    ).json()
    alfa["status"], alfa["amount"] = 2, 100  # «оплачен» 1 ₽ вместо 448 ₽
    assert (await client.get("/api/v1/payments/alfa/callback", params={"mdOrder": "bank-1"})).status_code == 502
    assert await db.scalar(select(Order.payment_status).where(Order.id == order["id"])) is PaymentStatus.PENDING


async def test_admin_rbac_finance_products_staff(client, db):
    tomato, _ = await shop(db)
    owner = await staff(client, db, SystemRole.OWNER, "owner@test.ru")
    manager = await staff(client, db, SystemRole.MANAGER, "manager@test.ru")
    picker = await staff(client, db, SystemRole.PICKER, "picker2@test.ru")
    buyer = await register(client)
    order = (await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 2)))).json()

    assert (await client.get("/api/v1/admin/orders", headers=picker)).status_code == 403
    assert (await client.get("/api/v1/admin/orders", headers=buyer)).status_code == 403
    orders = (await client.get("/api/v1/admin/orders", headers=manager)).json()
    assert orders[0]["number"] == order["number"] and orders[0]["customer_email"] == "buyer@test.ru"

    fin_owner = (await client.get("/api/v1/admin/finance", headers=owner, params={"days": 7})).json()
    assert fin_owner["current"]["revenue"] == "498.00" and fin_owner["current"]["orders"] == 1
    assert D(fin_owner["current"]["profit"]) > 0
    fin_manager = (await client.get("/api/v1/admin/finance", headers=manager, params={"days": 7})).json()
    assert fin_manager["current"]["profit"] is None  # у менеджера нет finance:view

    created = await client.post(
        "/api/v1/admin/products",
        headers=manager,
        json={
            "sku": "GR-0100",
            "name": "Огурцы",
            "cost_price": "90",
            "retail_price": "189",
            "stock": 20,
            "unit": "1 кг",
            "brand": "Агро Юг",
            "attributes": {"Страна": "Россия"},
            "image_url": "https://cdn.test/c.png",
        },
    )
    assert created.status_code == 201 and created.json()["margin_percent"] == 52.4
    pid = created.json()["id"]
    assert (await client.patch(f"/api/v1/admin/products/{pid}", headers=manager, json={"retail_price": "199"})).json()[
        "retail_price"
    ] == "199.00"
    assert (
        await client.post(
            "/api/v1/admin/products",
            headers=picker,
            json={"sku": "X", "name": "X", "cost_price": "1", "retail_price": "2"},
        )
    ).status_code == 403

    assert (
        await client.post(
            "/api/v1/admin/staff",
            headers=manager,
            json={"email": "n@test.ru", "full_name": "Новый Сотрудник", "role": "picker", "password": "Long-pass-123"},
        )
    ).status_code == 403
    new = await client.post(
        "/api/v1/admin/staff",
        headers=owner,
        json={"email": "n@test.ru", "full_name": "Новый Сотрудник", "role": "picker", "password": "Long-pass-123"},
    )
    assert new.status_code == 201
    me_id = (await client.get("/api/v1/auth/me", headers=owner)).json()["id"]
    assert (
        await client.patch(f"/api/v1/admin/staff/{me_id}", headers=owner, json={"is_active": False})
    ).status_code == 409


async def test_review_requires_delivered_purchase_then_moderation(client, db):
    tomato, _ = await shop(db)
    buyer = await register(client)
    owner = await staff(client, db, SystemRole.OWNER, "owner3@test.ru")
    assert (
        await client.post(f"/api/v1/products/{tomato.id}/reviews", headers=buyer, json={"rating": 5, "text": "Супер"})
    ).status_code == 403

    order = (await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 1)))).json()
    for s in ("picking", "shipped", "delivered"):
        assert (
            await client.patch(f"/api/v1/staff/orders/{order['id']}/status", headers=owner, json={"status": s})
        ).status_code == 200
    assert (
        await client.post(
            f"/api/v1/products/{tomato.id}/reviews", headers=buyer, json={"rating": 5, "text": "Сладкие!"}
        )
    ).status_code == 201
    assert (await client.get(f"/api/v1/products/{tomato.id}/reviews")).json() == []  # до модерации не видно

    pending = (await client.get("/api/v1/admin/reviews", headers=owner, params={"status": "pending"})).json()
    assert (
        await client.post(f"/api/v1/admin/reviews/{pending[0]['id']}/moderate", headers=owner, json={"approve": True})
    ).status_code == 204
    public = (await client.get(f"/api/v1/products/{tomato.id}/reviews")).json()
    assert public[0]["author"] == "Мария К." and public[0]["rating"] == 5
    item = (await client.get("/api/v1/products", params={"q": "Томаты"})).json()["items"][0]
    assert (item["rating"], item["reviews_count"]) == (5.0, 1)


async def test_login_bruteforce_is_rate_limited(client, db):
    await register(client, "victim@test.ru")
    codes = [
        (
            await client.post("/api/v1/auth/login", data={"username": "victim@test.ru", "password": f"wrong{i}"})
        ).status_code
        for i in range(7)
    ]
    assert codes[:4] == [401] * 4 and 429 in codes  # register тоже под лимитом /auth


async def test_cancel_restocks_and_b2b_approval_locks(client, db):
    """Регрессия: FOR UPDATE на модели с eager LEFT JOIN падал в Postgres (отмена заказа, одобрение B2B)."""
    from app.models import B2BAccount, B2BStatus, PriceList

    tomato, _ = await shop(db)
    owner = await staff(client, db, SystemRole.OWNER, "owner-cancel@test.ru")
    buyer = await register(client)
    order = (await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 4)))).json()
    assert await stock(db, tomato) == 6
    r = await client.patch(f"/api/v1/staff/orders/{order['id']}/status", headers=owner, json={"status": "cancelled"})
    assert r.status_code == 200, r.text
    assert await stock(db, tomato) == 10

    pl = PriceList(name="Опт")
    acc = B2BAccount(legal_name="ООО Ромашка", tax_id="7700000000")
    db.add_all([pl, acc])
    await db.commit()
    r = await client.post(
        f"/api/v1/admin/b2b-accounts/{acc.id}/decision", headers=owner, json={"approve": True, "price_list_id": pl.id}
    )
    assert r.status_code == 204, r.text
    assert await db.scalar(select(B2BAccount.status).where(B2BAccount.id == acc.id)) is B2BStatus.APPROVED
