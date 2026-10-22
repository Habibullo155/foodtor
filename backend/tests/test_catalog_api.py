from decimal import Decimal as D

from app.api.deps import get_optional_user
from app.main import app
from app.models import AccountType, B2BAccount, B2BStatus, PriceList, PriceListItem, RelationKind, User
from tests import factories as f


async def _catalog(db):
    veg = await f.category(db)
    phone = await f.product(db, "Томаты", "500", cat=veg)
    case = await f.product(db, "Укроп", "150", cat=veg)
    oos = await f.product(db, "Базилик", "70", cat=veg, stock=0)
    pro = await f.product(db, "Томаты Pro", "650", cat=veg)
    await f.relate(db, phone, case)
    await f.relate(db, phone, oos, position=1)
    await f.relate(db, phone, pro, RelationKind.UPSELL)
    pl = PriceList(name="Опт-1", default_discount_percent=D("0"))
    db.add(pl)
    await db.flush()
    db.add_all(
        [
            PriceListItem(price_list_id=pl.id, product_id=phone.id, min_quantity=1, unit_price=D("450")),
            PriceListItem(price_list_id=pl.id, product_id=phone.id, min_quantity=10, unit_price=D("430")),
            PriceListItem(price_list_id=pl.id, product_id=case.id, min_quantity=1, unit_price=D("90")),
        ]
    )
    await db.commit()
    return phone, pl


def _b2b(price_list_id, status=B2BStatus.APPROVED):
    return User(
        id=7,
        email="b@b.ru",
        full_name="Opt",
        account_type=AccountType.B2B,
        b2b_account=B2BAccount(id=1, legal_name="Shop", tax_id="1", status=status, price_list_id=price_list_id),
    )


async def test_anonymous_gets_retail_and_public_cache(client, db):
    phone, _ = await _catalog(db)
    r = await client.get(f"/api/v1/products/{phone.id}")
    assert r.status_code == 200
    body = r.json()
    assert body["audience"] == "anonymous"
    assert body["price"]["price"] == "500.00" and body["price"]["is_wholesale"] is False
    assert [p["name"] for p in body["cross_sell_products"]][0] == "Укроп"
    assert "Базилик" not in r.text  # нет в наличии
    assert [p["name"] for p in body["upsell_products"]] == ["Томаты Pro"]
    assert "cost_price" not in r.text
    assert r.headers["cache-control"].startswith("public")


async def test_verified_b2b_gets_wholesale_everywhere(client, db):
    phone, pl = await _catalog(db)
    app.dependency_overrides[get_optional_user] = lambda: _b2b(pl.id)
    try:
        body = (await client.get(f"/api/v1/products/{phone.id}")).json()
    finally:
        app.dependency_overrides.pop(get_optional_user)
    assert body["audience"] == "b2b"
    assert (body["price"]["price"], body["price"]["compare_at_price"]) == ("450.00", "500.00")
    assert [t["min_quantity"] for t in body["price"]["tiers"]] == [1, 10]
    dill = body["cross_sell_products"][0]["price"]
    assert (dill["price"], dill["compare_at_price"]) == ("90.00", "150.00")


async def test_pending_b2b_sees_retail_and_private_cache(client, db):
    phone, pl = await _catalog(db)
    app.dependency_overrides[get_optional_user] = lambda: _b2b(pl.id, B2BStatus.PENDING)
    try:
        r = await client.get(f"/api/v1/products/{phone.id}")
    finally:
        app.dependency_overrides.pop(get_optional_user)
    assert r.json()["audience"] == "b2c" and r.json()["price"]["is_wholesale"] is False
    assert r.headers["cache-control"].startswith("private")


async def test_recommendations_and_404(client, db):
    phone, _ = await _catalog(db)
    r = await client.get("/api/v1/products/recommendations", params=[("ids", phone.id), ("ids", phone.id)])
    assert [p["name"] for p in r.json()["products"]][0] == "Укроп"
    assert (await client.get("/api/v1/products/999")).status_code == 404
    assert (await client.get("/api/v1/products/recommendations")).status_code == 422
