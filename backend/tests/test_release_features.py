from app.models import SystemRole
from tests import factories as f
from tests.test_release_flows import checkout_body, register, shop, staff

SHOP = {
    "contact_phone": "+7 (985) 394-72-62",
    "contact_email": "hello@foodtor.ru",
    "delivery_min_order": "2500",
    "courier_fee": "199",
    "free_delivery_from": "5000",
    "express_enabled": False,
    "express_fee": "349",
    "express_hours": 3,
    "pickup_enabled": True,
    "legal_name": "ИП Иванов Иван Иванович",
    "legal_inn": "771234567859",
    "legal_ogrn": "",
    "legal_address": "",
}


async def _phone_signup(client, phone: str, name: str, ref: str | None = None) -> dict:
    sent = (await client.post("/api/v1/auth/phone/request", json={"phone": phone})).json()
    v = (await client.post("/api/v1/auth/phone/verify", json={"phone": phone, "code": sent["dev_code"]})).json()
    done = await client.post(
        "/api/v1/auth/phone/complete", json={"signup_token": v["signup_token"], "full_name": name, "ref": ref}
    )
    return {"Authorization": f"Bearer {done.json()['access_token']}"}


async def test_shop_settings_drive_site_and_checkout(client, db):
    tomato, dill = await shop(db)
    tomato.stock = 100
    await db.commit()
    owner = await staff(client, db, SystemRole.OWNER, "owner-shop@test.ru")
    manager = await staff(client, db, SystemRole.MANAGER, "manager-shop@test.ru")
    buyer = await register(client)

    assert (await client.put("/api/v1/admin/settings/shop", headers=manager, json=SHOP)).status_code == 403
    bad = await client.put("/api/v1/admin/settings/shop", headers=owner, json=SHOP | {"legal_inn": "123"})
    assert bad.status_code == 422
    assert (await client.put("/api/v1/admin/settings/shop", headers=owner, json=SHOP)).status_code == 200
    got = (await client.get("/api/v1/admin/settings/shop", headers=owner)).json()
    assert got["contact_email"] == "hello@foodtor.ru" and got["express_hours"] == 3

    home = (await client.get("/")).text.replace("\xa0", " ")
    assert 'href="tel:+79853947262"' in home and "hello@foodtor.ru" in home
    assert "заказ от 2 500" in home and "ИП Иванов Иван Иванович, ИНН 771234567859" in home
    delivery = (await client.get("/info/delivery")).text.replace("\xa0", " ")
    assert "<b>Экспресс</b>" not in delivery and "от <b>2 500" in delivery
    cart = (await client.get("/cart")).text
    assert 'value="express"' not in cart and 'value="pickup"' in cart
    offer = (await client.get("/info/offer")).text
    assert "ИП Иванов Иван Иванович" in offer and "771234567859" in offer

    small = checkout_body((tomato, 2))  # 498 ₽ — меньше минимальной суммы доставки
    quote = (
        await client.post("/api/v1/me/orders/quote", headers=buyer, json={"items": small["items"], "delivery": "courier"})
    ).json()
    assert quote["delivery_min_order"] == "2500.00" and "Добавьте товаров ещё на 2002" in quote["delivery_problem"]
    r = await client.post("/api/v1/me/orders", headers=buyer, json=small)
    assert r.status_code == 409 and "от 2500" in r.json()["detail"]
    express = await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 10), delivery="express"))
    assert express.status_code == 409 and "Экспресс" in express.json()["detail"]
    pickup = await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 1), delivery="pickup"))
    assert pickup.status_code == 201  # самовывоз — на любую сумму
    big = await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 11)))
    assert big.status_code == 201 and big.json()["delivery_fee"] == "199.00"  # 2739 ₽ < 5000 — курьер платный


async def test_referral_program(client, db):
    tomato, _ = await shop(db)
    tomato.stock = 100
    await db.commit()
    owner = await staff(client, db, SystemRole.OWNER, "owner-ref@test.ru")
    settings = {
        "referral_enabled": True,
        "referral_friend_amount": "300",
        "referral_inviter_amount": "500",
        "referral_min_order": "1000",
    }
    assert (await client.put("/api/v1/admin/settings/referral", headers=owner, json=settings)).status_code == 200

    inviter = await register(client, "inviter@test.ru")
    mine = (await client.get("/api/v1/me/referral", headers=inviter)).json()
    assert len(mine["code"]) == 7 and mine["promos"] == [] and mine["invited"] == 0

    friend = await _phone_signup(client, "+79161112200", "Друг", ref=mine["code"].lower())
    stranger = await _phone_signup(client, "+79161112201", "Без ссылки", ref="NOPE123")
    friend_promo = (await client.get("/api/v1/me/referral", headers=friend)).json()["promos"]
    assert [(p["amount"], p["first_order_only"]) for p in friend_promo] == [("300.00", True)]
    assert (await client.get("/api/v1/me/referral", headers=stranger)).json()["promos"] == []
    code = friend_promo[0]["code"]

    # чужой личный промокод — как будто его нет
    stolen = await client.post(
        "/api/v1/me/orders/quote", headers=stranger, json={"items": [{"product_id": tomato.id, "quantity": 5}], "promo_code": code}
    )
    assert stolen.json()["promo_error"] == "Промокод не найден"

    order = (await client.post("/api/v1/me/orders", headers=friend, json=checkout_body((tomato, 5), promo=code))).json()
    assert order["total"] == str(249 * 5 - 300 + 199) + ".00"
    again = await client.post("/api/v1/me/orders", headers=friend, json=checkout_body((tomato, 5), promo=code))
    assert again.status_code == 409

    assert (await client.get("/api/v1/me/referral", headers=inviter)).json()["promos"] == []  # бонус — после получения
    for s in ("picking", "shipped", "delivered"):
        await client.patch(f"/api/v1/staff/orders/{order['id']}/status", headers=owner, json={"status": s})
    me = (await client.get("/api/v1/me/referral", headers=inviter)).json()
    assert (me["invited"], me["rewarded"]) == (1, 1)
    assert [(p["amount"], p["source"]) for p in me["promos"]] == [("500.00", "referral_inviter")]

    # второй заказ друга бонус не повторяет
    second = (await client.post("/api/v1/me/orders", headers=friend, json=checkout_body((tomato, 5)))).json()
    for s in ("picking", "shipped", "delivered"):
        await client.patch(f"/api/v1/staff/orders/{second['id']}/status", headers=owner, json={"status": s})
    assert len((await client.get("/api/v1/me/referral", headers=inviter)).json()["promos"]) == 1

    friends_page = (await client.get("/friends")).text
    assert "получите 500" in friends_page
    settings["referral_enabled"] = False
    await client.put("/api/v1/admin/settings/referral", headers=owner, json=settings)
    assert (await client.get("/friends")).status_code == 404


async def test_banners_on_home(client, db):
    manager = await staff(client, db, SystemRole.MANAGER, "manager-ban@test.ru")
    picker = await staff(client, db, SystemRole.PICKER, "picker-ban@test.ru")
    banner = {"title": "Неделя ягод", "text": "Клубника −20%", "button_label": "Смотреть", "link_url": "/promo"}
    assert (await client.post("/api/v1/admin/banners", headers=picker, json=banner)).status_code == 403
    bad = await client.post("/api/v1/admin/banners", headers=manager, json=banner | {"link_url": "javascript:alert(1)"})
    assert bad.status_code == 422
    a = (await client.post("/api/v1/admin/banners", headers=manager, json=banner)).json()
    b = (await client.post("/api/v1/admin/banners", headers=manager, json=banner | {"title": "Скрытый", "is_active": False})).json()
    home = (await client.get("/")).text
    assert "Неделя ягод" in home and "Скрытый" not in home and 'href="/promo"' in home
    assert [x["title"] for x in (await client.get("/api/v1/banners")).json()] == ["Неделя ягод"]
    await client.put(f"/api/v1/admin/banners/{b['id']}", headers=manager, json=banner | {"title": "Осень"})
    await client.put("/api/v1/admin/banners-order", headers=manager, json={"ids": [b["id"], a["id"]]})
    assert [x["title"] for x in (await client.get("/api/v1/banners")).json()] == ["Осень", "Неделя ягод"]
    assert (await client.delete(f"/api/v1/admin/banners/{a['id']}", headers=manager)).status_code == 204


async def test_support_chat(client, db):
    manager = await staff(client, db, SystemRole.MANAGER, "manager-sup@test.ru")
    picker = await staff(client, db, SystemRole.PICKER, "picker-sup@test.ru")
    buyer = await register(client, "help@test.ru")
    assert (await client.get("/support")).status_code == 200

    thread = (await client.post("/api/v1/me/support", headers=buyer, json={"text": "  Где мой заказ?  "})).json()
    assert [(m["text"], m["from_staff"]) for m in thread] == [("Где мой заказ?", False)]
    assert (await client.post("/api/v1/me/support", headers=buyer, json={"text": "   "})).status_code == 422
    assert (await client.get("/api/v1/admin/support", headers=picker)).status_code == 403

    inbox = (await client.get("/api/v1/admin/support", headers=manager)).json()
    assert [(t["name"], t["unread"], t["last_text"]) for t in inbox] == [("Мария Кузнецова", 1, "Где мой заказ?")]
    uid = inbox[0]["user_id"]
    await client.post(f"/api/v1/admin/support/{uid}", headers=manager, json={"text": "Курьер уже едет"})
    assert (await client.get("/api/v1/admin/support", headers=manager)).json()[0]["unread"] == 0
    assert (await client.get("/api/v1/me/support/unread", headers=buyer)).json() == {"unread": 1}
    mine = (await client.get("/api/v1/me/support", headers=buyer)).json()
    assert mine[-1]["from_staff"] and mine[-1]["author"] == "Manager"
    assert (await client.get("/api/v1/me/support/unread", headers=buyer)).json() == {"unread": 0}


async def test_online_payment_is_invisible_until_configured(client, db):
    tomato, _ = await shop(db)
    buyer = await register(client, "pay@test.ru")
    for path in ("/api/v1/payments/alfa/return?orderId=x", "/api/v1/payments/alfa/callback?mdOrder=x", "/payment/return"):
        assert (await client.get(path)).status_code == 404, path
    r = await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 1), payment="card_online"))
    assert r.status_code == 422 and r.json()["detail"] == "Выберите способ оплаты"
    for path in ("/checkout", "/info/payment", "/info/privacy", "/info/offer", "/"):
        html = (await client.get(path)).text.lower()
        assert "card_online" not in html and "альфа" not in html and "онлайн" not in html, path
    assert "online" not in str((await client.get("/api/v1/shop/options")).json())


async def test_category_photo(client, db):
    cat = await f.category(db, "Фрукты")
    await f.product(db, "Яблоки", "100", cat=cat)
    await db.commit()
    manager = await staff(client, db, SystemRole.MANAGER, "manager-cat@test.ru")
    body = {"name": "Фрукты", "slug": "frukty", "image_url": "/media/banners/abc.webp"}
    assert (await client.patch(f"/api/v1/admin/categories/{cat.id}", headers=manager, json=body)).status_code == 200
    assert 'src="/media/banners/abc.webp"' in (await client.get("/")).text
    bad = body | {"image_url": "javascript:alert(1)"}
    assert (await client.patch(f"/api/v1/admin/categories/{cat.id}", headers=manager, json=bad)).status_code == 422
