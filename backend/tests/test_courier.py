from app.models import SystemRole
from tests.conftest import FAKE_PLACES
from tests.test_release_flows import checkout_body, register, shop, staff

MSK = FAKE_PLACES["москва"]


async def _shipped_order(client, db):
    tomato, _ = await shop(db)
    owner = await staff(client, db, SystemRole.OWNER, "owner-c@test.ru")
    buyer = await register(client)
    order = (await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 2)))).json()
    for s in ("picking", "shipped"):
        r = await client.patch(f"/api/v1/staff/orders/{order['id']}/status", headers=owner, json={"status": s})
        assert r.status_code == 200, r.text
    return order, buyer, owner


async def test_courier_flow_phone_hidden_until_near(client, db):
    order, buyer, owner = await _shipped_order(client, db)
    courier = await staff(client, db, SystemRole.COURIER, "courier@test.ru")
    other = await staff(client, db, SystemRole.COURIER, "courier2@test.ru")
    url = f"/api/v1/courier/orders/{order['id']}"

    # покупатель и сборщик/клиент не имеют доступа к курьерским эндпоинтам
    assert (await client.get("/api/v1/courier/orders", headers=buyer)).status_code == 403

    listed = (await client.get("/api/v1/courier/orders", headers=courier)).json()
    o = next(x for x in listed if x["id"] == order["id"])
    assert o["phone"] is None and o["phone_masked"].endswith("00") and o["customer_name"] == "Мария"
    assert o["cash_to_collect"] is not None and o["dest_lat"] is not None

    assert (await client.post(f"{url}/chat", headers=courier, json={"text": "Еду"})).status_code == 403  # ещё не мой
    took = (await client.post(f"{url}/take", headers=courier)).json()
    assert took["mine"] is True
    assert (await client.post(f"{url}/take", headers=other)).status_code == 409
    assert order["id"] not in [x["id"] for x in (await client.get("/api/v1/courier/orders", headers=other)).json()]

    far = (await client.post(f"{url}/location", headers=courier, json={"lat": 55.9, "lng": 37.4})).json()
    assert far["phone"] is None and far["distance_km"] > 1
    near = (await client.post(f"{url}/location", headers=courier, json={"lat": MSK[0] + 0.003, "lng": MSK[1]})).json()
    assert near["phone"] == "+7 900 000-00-00" and "рядом" in near["phone_reveal_reason"]

    info = (await client.get(f"/api/v1/me/orders/{order['id']}/courier", headers=buyer)).json()
    assert info["assigned"] and info["courier_name"] == "Courier" and info["phone_opened"] and info["distance_km"] < 1


async def test_emergency_reveals_phone_with_reason_and_chat(client, db):
    order, buyer, owner = await _shipped_order(client, db)
    courier = await staff(client, db, SystemRole.COURIER, "courier@test.ru")
    url = f"/api/v1/courier/orders/{order['id']}"
    await client.post(f"{url}/take", headers=courier)

    # чат до ЧП — обычный, без телефонов
    assert (
        await client.post(
            f"/api/v1/me/orders/{order['id']}/courier-chat", headers=buyer, json={"text": "Код домофона 45К"}
        )
    ).status_code == 201
    chat = (await client.post(f"{url}/chat", headers=courier, json={"text": "Понял, буду через 10 минут"})).json()
    assert [m["from_staff"] for m in chat] == [False, True] and chat[1]["author"] == "Курьер Courier"

    assert (await client.post(f"{url}/emergency", headers=courier, json={"reason": "да"})).status_code == 422
    em = (
        await client.post(
            f"{url}/emergency", headers=courier, json={"reason": "Не отвечает в чате, домофон не работает"}
        )
    ).json()
    assert em["phone"] and em["phone_reveal_reason"].startswith("ЧП:")
    buyer_chat = (await client.get(f"/api/v1/me/orders/{order['id']}/courier-chat", headers=buyer)).json()
    assert "открыл ваш номер" in buyer_chat[-1]["text"]
    shop_thread = (await client.get(f"/api/v1/admin/orders/{order['id']}/comments", headers=owner)).json()
    assert any("[ЧП курьера]" in m["text"] for m in shop_thread)
    # курьерский чат не смешивается с перепиской с магазином
    assert not any("домофона" in m["text"] for m in shop_thread)

    done = await client.post(f"{url}/delivered", headers=courier)
    assert done.status_code == 200 and done.json()["status"] == "delivered"
    admin = (await client.get(f"/api/v1/admin/orders/{order['id']}", headers=owner)).json()
    assert admin["payment_status"] == "paid"  # наличные получены при вручении
    closed = await client.post(f"/api/v1/me/orders/{order['id']}/courier-chat", headers=buyer, json={"text": "?"})
    assert closed.status_code == 409


async def test_delivery_cities_extend_radius(client, db):
    tomato, _ = await shop(db)
    owner = await staff(client, db, SystemRole.OWNER, "owner-city@test.ru")
    buyer = await register(client)
    put = "/api/v1/admin/settings/delivery"
    tula = checkout_body((tomato, 1)) | {"address": "г. Тула, ул. Ленина, 1"}

    await client.put(put, headers=owner, json={"radius_km": 10})
    assert (await client.post("/api/v1/me/orders", headers=buyer, json=tula)).status_code == 409
    zone = (await client.put(put, headers=owner, json={"radius_km": 10, "cities": ["Тула", "тула", "Химки"]})).json()
    assert zone["cities"] == ["Тула", "Химки"]
    check = (await client.post("/api/v1/delivery/check", json={"address": "Тула, Ленина 1"})).json()
    assert check["ok"] and check["city"] == "Тула"
    assert (await client.post("/api/v1/me/orders", headers=buyer, json=tula)).status_code == 201
    # «Тульская область» — не город Тула: остаётся проверка радиусом
    region = (await client.post("/api/v1/delivery/check", json={"address": "Тульская область, Новомосковск"})).json()
    assert region["ok"] is False
