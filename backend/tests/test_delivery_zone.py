from app.models import SystemRole
from app.services import geo
from app.services.geo import Point, haversine_km
from tests.test_release_flows import checkout_body, register, shop, staff


def test_haversine_moscow_tula():
    assert 165 < haversine_km(Point(55.7558, 37.6176), Point(54.1931, 37.6177)) < 180


async def test_public_check_inside_outside_unknown(client, db):
    ok = (await client.post("/api/v1/delivery/check", json={"address": "Москва, Тверская 1"})).json()
    assert ok["ok"] is True and ok["distance_km"] < 1 and ok["radius_km"] == 20
    far = (await client.post("/api/v1/delivery/check", json={"address": "Тула, Ленина 1"})).json()
    assert far["ok"] is False and "не доставляем" in far["reason"] and far["distance_km"] > 160
    unknown = (await client.post("/api/v1/delivery/check", json={"address": "Нигдеград, ул. Мира, 1"})).json()
    assert unknown["ok"] is False and "Не нашли" in unknown["reason"]


async def test_checkout_rejects_outside_zone_but_allows_pickup(client, db):
    tomato, _ = await shop(db)
    buyer = await register(client)
    body = checkout_body((tomato, 1)) | {"address": "Тула, ул. Ленина, 1"}
    r = await client.post("/api/v1/me/orders", headers=buyer, json=body)
    assert r.status_code == 409 and "не доставляем" in r.json()["detail"]
    pickup = await client.post("/api/v1/me/orders", headers=buyer, json=body | {"delivery": "pickup"})
    assert pickup.status_code == 201


async def test_owner_changes_radius_and_center(client, db):
    tomato, _ = await shop(db)
    owner = await staff(client, db, SystemRole.OWNER, "owner-zone@test.ru")
    manager = await staff(client, db, SystemRole.MANAGER, "manager-zone@test.ru")
    buyer = await register(client)
    khimki = checkout_body((tomato, 1)) | {"address": "Химки, Ленинский пр-т, 1"}

    assert (
        await client.put("/api/v1/admin/settings/delivery", headers=manager, json={"radius_km": 5})
    ).status_code == 403
    r = await client.put("/api/v1/admin/settings/delivery", headers=owner, json={"radius_km": 10})
    assert r.json()["radius_km"] == 10
    assert (await client.post("/api/v1/me/orders", headers=buyer, json=khimki)).status_code == 409  # ~19 км > 10

    await client.put("/api/v1/admin/settings/delivery", headers=owner, json={"radius_km": 25})
    assert (await client.post("/api/v1/me/orders", headers=buyer, json=khimki)).status_code == 201

    moved = (
        await client.put(
            "/api/v1/admin/settings/delivery", headers=owner, json={"radius_km": 25, "store_address": "Тула, склад"}
        )
    ).json()
    assert round(moved["lat"], 2) == 54.19  # центр перенесён по геокодеру
    bad = await client.put(
        "/api/v1/admin/settings/delivery", headers=owner, json={"radius_km": 25, "store_address": "Нигдеград"}
    )
    assert bad.status_code == 422

    await client.put("/api/v1/admin/settings/delivery", headers=owner, json={"radius_km": 25, "enabled": False})
    assert (
        await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 1)) | {"address": "Тула, 1"})
    ).status_code == 201


async def test_geocoder_outage_does_not_block_orders(client, db, monkeypatch):
    import httpx

    tomato, _ = await shop(db)
    buyer = await register(client)
    monkeypatch.setattr(geo, "TEST_TRANSPORT", httpx.MockTransport(lambda r: httpx.Response(503)))
    r = await client.post(
        "/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 1)) | {"address": "Где-то, ул. Лесная, 5"}
    )
    assert r.status_code == 201


async def test_saved_address_gets_zone_flag(client, db):
    buyer = await register(client)
    near = (await client.post("/api/v1/me/addresses", headers=buyer, json={"address": "Москва, Арбат 5"})).json()
    far = (await client.post("/api/v1/me/addresses", headers=buyer, json={"address": "Тула, Ленина 1"})).json()
    assert near["in_zone"] is True and far["in_zone"] is False and "не доставляем" in far["zone_message"]


async def test_cash_order_becomes_paid_on_delivery_and_payment_status_visible(client, db):
    tomato, _ = await shop(db)
    owner = await staff(client, db, SystemRole.OWNER, "owner-cash@test.ru")
    buyer = await register(client)
    order = (await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 1)))).json()
    for s in ("picking", "shipped", "delivered"):
        await client.patch(f"/api/v1/staff/orders/{order['id']}/status", headers=owner, json={"status": s})
    admin = (await client.get(f"/api/v1/admin/orders/{order['id']}", headers=owner)).json()
    assert (admin["payment_method"], admin["payment_status"]) == ("cash", "paid")

    # пока эквайринг не подключён, о нём не знает никто — даже админка
    assert (await client.get("/api/v1/admin/settings/payments", headers=owner)).status_code == 404


async def test_check_by_map_point_and_reverse(client, db):
    tomato, _ = await shop(db)
    buyer = await register(client)
    near = (await client.post("/api/v1/delivery/check", json={"lat": 55.76, "lng": 37.62})).json()
    assert near["ok"] is True and near["distance_km"] < 2
    far = (await client.post("/api/v1/delivery/check", json={"lat": 54.19, "lng": 37.61})).json()
    assert far["ok"] is False and "не доставляем" in far["reason"]
    assert (await client.post("/api/v1/delivery/check", json={})).status_code == 422

    rev = (await client.get("/api/v1/delivery/reverse", params={"lat": 55.7558, "lng": 37.6176})).json()
    assert rev["address"] == "Москва, Тестовая улица, 1"
    assert (rev["city"], rev["street"], rev["house"]) == ("Москва", "Тестовая улица", "1")

    # строка адреса «непонятная», но точка с карты внутри зоны → заказ принимается, курьер получит координаты
    body = checkout_body((tomato, 1)) | {"address": "дом у парка, 3 подъезд", "lat": 55.757, "lng": 37.619}
    r = await client.post("/api/v1/me/orders", headers=buyer, json=body)
    assert r.status_code == 201
    far_body = body | {"lat": 54.19, "lng": 37.61}
    assert (await client.post("/api/v1/me/orders", headers=buyer, json=far_body)).status_code == 409

    saved = (
        await client.post(
            "/api/v1/me/addresses", headers=buyer, json={"address": "дом у парка", "lat": 55.757, "lng": 37.619}
        )
    ).json()
    assert saved["in_zone"] is True and saved["lat"] == 55.757


async def test_city_alone_is_not_an_address(client, db):
    """«Москва» (даже из списка городов) — не адрес: нужен дом, иначе курьеру некуда ехать."""
    tomato, _ = await shop(db)
    buyer = await register(client)
    for bad in ("Москва", "Москва, 5", "Тверская"):
        r = (await client.post("/api/v1/delivery/check", json={"address": bad})).json()
        assert r["ok"] is False and "номер дома" in r["reason"], bad
    no_house = (await client.post("/api/v1/delivery/check", json={"address": "Москва, Тверская улица"})).json()
    assert no_house["ok"] is False and "номер дома" in no_house["reason"]
    assert (await client.post("/api/v1/delivery/check", json={"address": "Москва, Тверская, 1"})).json()["ok"] is True

    order = await client.post(
        "/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 1)) | {"address": "Москва"}
    )
    assert order.status_code == 409 and "номер дома" in order.json()["detail"]
    # самовывоз адреса не требует
    pickup = checkout_body((tomato, 1)) | {"address": "Самовывоз", "delivery": "pickup"}
    assert (await client.post("/api/v1/me/orders", headers=buyer, json=pickup)).status_code == 201
