from decimal import Decimal

from sqlalchemy import select

from app.api.v1.b2b import inn_is_valid
from app.models import SystemRole
from tests import factories as f
from tests.test_release_flows import checkout_body, register, staff

COMPANY = {"legal_name": "ООО «Зелёная ложка»", "tax_id": "7704123450"}


def test_inn_checksum():
    assert inn_is_valid("7704123450")
    assert inn_is_valid("771234567859")
    assert not inn_is_valid("7704123451")
    assert not inn_is_valid("12345")
    assert not inn_is_valid("77041234ab")


async def test_wholesale_client_sees_own_prices_and_min_order(client, db):
    veg = await f.category(db, "Овощи")
    tomato = await f.product(db, "Томаты", "200", cat=veg, stock=500)
    rice = await f.product(db, "Рис", "100", cat=veg, stock=500)
    await db.commit()

    owner = await staff(client, db, SystemRole.OWNER, "owner-b2b@test.ru")
    manager = await staff(client, db, SystemRole.MANAGER, "manager-b2b@test.ru")
    buyer = await register(client, "cafe@test.ru")

    # оптовая цена задаётся прямо в товаре
    r = await client.patch(f"/api/v1/admin/products/{tomato.id}", headers=owner, json={"wholesale_price": "150"})
    assert r.status_code == 200 and r.json()["wholesale_price"] == "150.00"

    bad = await client.post("/api/v1/me/b2b-application", headers=buyer, json=COMPANY | {"tax_id": "7704123451"})
    assert bad.status_code == 422 and "ИНН" in bad.text
    r = await client.post("/api/v1/me/b2b-application", headers=buyer, json=COMPANY | {"tax_id": "77 0412 3450"})
    assert r.status_code == 201, r.text
    assert r.json() == {"status": "pending", "legal_name": "ООО «Зелёная ложка»", "tax_id": "7704123450"}
    again = await client.post("/api/v1/me/b2b-application", headers=buyer, json=COMPANY)
    assert again.status_code == 409 and again.json()["detail"] == "Заявка уже отправлена"
    me = (await client.get("/api/v1/auth/me", headers=buyer)).json()
    assert me["account_type"] == "b2b" and me["b2b"]["status"] == "pending"

    other = await register(client, "rival@test.ru")
    dup = await client.post("/api/v1/me/b2b-application", headers=other, json=COMPANY)
    assert dup.status_code == 409 and "ИНН" in dup.json()["detail"]
    assert (await client.post("/api/v1/me/b2b-application", headers=manager, json=COMPANY)).status_code == 403

    prices_url = f"/api/v1/products/prices?ids={tomato.id}&ids={rice.id}"
    pending = (await client.get(prices_url, headers=buyer)).json()
    assert pending["audience"] == "b2c"  # заявка на проверке — розничные цены
    assert {i["price"]["price"] for i in pending["items"]} == {"200.00", "100.00"}

    companies = (await client.get("/api/v1/admin/b2b-accounts", headers=manager)).json()
    assert [(c["legal_name"], c["status"], c["members"][0]["email"]) for c in companies] == [
        ("ООО «Зелёная ложка»", "pending", "cafe@test.ru")
    ]
    decision = f"/api/v1/admin/b2b-accounts/{companies[0]['id']}/decision"
    assert (await client.post(decision, headers=manager, json={"approve": True})).status_code == 204

    approved = (await client.get(prices_url, headers=buyer)).json()
    by_id = {i["id"]: i["price"] for i in approved["items"]}
    assert approved["audience"] == "b2b"
    assert (by_id[tomato.id]["price"], by_id[tomato.id]["compare_at_price"]) == ("150.00", "200.00")
    assert by_id[tomato.id]["is_wholesale"] is True
    assert (by_id[rice.id]["price"], by_id[rice.id]["is_wholesale"]) == ("100.00", False)  # без оптовой цены
    assert (await client.get(prices_url, headers=other)).json()["audience"] == "b2c"

    settings_url = "/api/v1/admin/settings/wholesale"
    assert (await client.get(settings_url, headers=manager)).json() == {"min_order": "5000.00"}
    picker = await staff(client, db, SystemRole.PICKER, "picker-b2b@test.ru")
    assert (await client.put(settings_url, headers=picker, json={"min_order": "1"})).status_code == 403
    assert (await client.put(settings_url, headers=manager, json={"min_order": "1000"})).json() == {
        "min_order": "1000.00"
    }

    small = {"items": [{"product_id": tomato.id, "quantity": 2}]}
    quote = (await client.post("/api/v1/me/orders/quote", headers=buyer, json=small)).json()
    assert quote["subtotal"] == "300.00" and quote["wholesale"] is True and quote["wholesale_min_order"] == "1000.00"
    retail_quote = (await client.post("/api/v1/me/orders/quote", headers=other, json=small)).json()
    assert retail_quote["wholesale"] is False and retail_quote["wholesale_min_order"] is None

    small_order = checkout_body((tomato, 2))
    r = await client.post("/api/v1/me/orders", headers=buyer, json=small_order)
    assert r.status_code == 409 and r.json()["detail"] == "Минимальный заказ для оптовых клиентов — 1000 ₽"
    r = await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 10)))
    assert r.status_code == 201, r.text
    assert [(i["unit_price"], i["line_total"]) for i in r.json()["items"]] == [("150.00", "1500.00")]
    # розничный покупатель минимальным заказом оптовика не ограничен
    assert (await client.post("/api/v1/me/orders", headers=other, json=small_order)).status_code == 201


async def test_rejected_company_can_apply_again(client, db):
    owner = await staff(client, db, SystemRole.OWNER, "owner-b2b2@test.ru")
    buyer = await register(client, "shop@test.ru")
    await client.post("/api/v1/me/b2b-application", headers=buyer, json=COMPANY)
    acc = (await client.get("/api/v1/admin/b2b-accounts", headers=owner)).json()[0]
    await client.post(f"/api/v1/admin/b2b-accounts/{acc['id']}/decision", headers=owner, json={"approve": False})
    fixed = COMPANY | {"legal_name": "ИП Соколова Е. А.", "tax_id": "771234567859"}
    r = await client.post("/api/v1/me/b2b-application", headers=buyer, json=fixed)
    assert r.status_code == 201 and r.json()["status"] == "pending"
    companies = (await client.get("/api/v1/admin/b2b-accounts", headers=owner)).json()
    assert [(c["id"], c["legal_name"]) for c in companies] == [(acc["id"], "ИП Соколова Е. А.")]


async def test_import_sets_wholesale_price_and_keeps_it_when_column_missing(db):
    from app.models import Product
    from app.repositories.product import ProductRepository
    from app.services.import_export import ProductImportService

    service = ProductImportService(ProductRepository(db))
    with_opt = "Артикул;Название;Себестоимость;Цена;Оптовая цена\nW-1;Мука;40;90;70\n"
    await service.import_file("p.csv", with_opt.encode())
    without = "Артикул;Название;Себестоимость;Цена\nW-1;Мука;40;95\n"
    await service.import_file("p.csv", without.encode())
    db.expire_all()
    flour = (await db.scalars(select(Product).where(Product.sku == "W-1"))).unique().one()
    assert (flour.retail_price, flour.wholesale_price) == (Decimal("95.00"), Decimal("70.00"))
