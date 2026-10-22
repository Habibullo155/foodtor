import io

import pytest
from PIL import Image

from app.core.config import get_settings
from app.models import SystemRole
from tests.test_release_flows import checkout_body, register, shop, staff


@pytest.fixture(autouse=True)
def media_tmp(tmp_path, monkeypatch):
    monkeypatch.setattr(get_settings(), "media_root", str(tmp_path))


def png_with_exif() -> bytes:
    img = Image.new("RGB", (800, 400), "red")
    exif = Image.Exif()
    exif[0x8825] = {2: (55, 45, 0)}  # GPSInfo — геометка, не должна утечь
    buf = io.BytesIO()
    img.save(buf, "JPEG", exif=exif)
    return buf.getvalue()


async def test_profile_and_avatar(client, tmp_path):
    h = await register(client)
    r = await client.patch(
        "/api/v1/me/profile", headers=h, json={"full_name": "Мария Иванова", "phone": "+7 900 111-22-33"}
    )
    assert r.json()["full_name"] == "Мария Иванова"

    bad = await client.post("/api/v1/me/avatar", headers=h, files={"file": ("x.png", b"<?php echo 1; ?>", "image/png")})
    assert bad.status_code == 422  # расширение/Content-Type не помогают — проверяется содержимое

    ok = await client.post("/api/v1/me/avatar", headers=h, files={"file": ("me.jpg", png_with_exif(), "image/jpeg")})
    url = ok.json()["avatar_url"]
    assert url.startswith("/media/avatars/") and url.endswith(".webp")
    saved = Image.open(tmp_path / "avatars" / url.rsplit("/", 1)[1])
    assert saved.size == (256, 256) and not saved.getexif()  # квадрат, EXIF (GPS) вычищен
    assert (await client.get("/api/v1/auth/me", headers=h)).json()["avatar_url"] == url

    again = (
        await client.post("/api/v1/me/avatar", headers=h, files={"file": ("2.jpg", png_with_exif(), "image/jpeg")})
    ).json()
    assert len(list((tmp_path / "avatars").iterdir())) == 1  # старый файл удалён
    assert (await client.delete("/api/v1/me/avatar", headers=h)).json()["avatar_url"] is None
    assert not (tmp_path / "avatars" / again["avatar_url"].rsplit("/", 1)[1]).exists()


async def test_addresses_default_and_isolation(client):
    me = await register(client)
    other = await register(client, "other@test.ru")
    a1 = (
        await client.post("/api/v1/me/addresses", headers=me, json={"address": "Москва, Тверская 1", "apartment": "12"})
    ).json()
    assert a1["is_default"] is True and a1["one_line"] == "Москва, Тверская 1, кв. 12"
    a2 = (
        await client.post(
            "/api/v1/me/addresses",
            headers=me,
            json={"label": "Работа", "address": "Москва, Арбат 5", "is_default": True},
        )
    ).json()
    lst = (await client.get("/api/v1/me/addresses", headers=me)).json()
    assert [a["id"] for a in lst] == [a2["id"], a1["id"]] and [a["is_default"] for a in lst] == [True, False]

    assert (
        await client.put(f"/api/v1/me/addresses/{a1['id']}", headers=other, json={"address": "взлом"})
    ).status_code == 404
    assert (await client.delete(f"/api/v1/me/addresses/{a1['id']}", headers=other)).status_code == 404

    assert (await client.delete(f"/api/v1/me/addresses/{a2['id']}", headers=me)).status_code == 204
    assert (await client.get("/api/v1/me/addresses", headers=me)).json()[0]["is_default"] is True  # основной передан


async def test_purchases_only_from_delivered_orders(client, db):
    tomato, dill = await shop(db)
    buyer = await register(client)
    owner = await staff(client, db, SystemRole.OWNER, "owner-p@test.ru")
    delivered = (
        await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 2), (dill, 1)))
    ).json()
    await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((dill, 1)))  # не доставлен
    for s in ("picking", "shipped", "delivered"):
        await client.patch(f"/api/v1/staff/orders/{delivered['id']}/status", headers=owner, json={"status": s})

    items = (await client.get("/api/v1/me/purchases", headers=buyer)).json()
    by_name = {i["name"]: i for i in items}
    assert set(by_name) == {"Томаты", "Укроп"}
    assert (by_name["Томаты"]["total_quantity"], by_name["Укроп"]["times_bought"]) == (2, 1)
    assert by_name["Томаты"]["price"] == "249.00" and by_name["Томаты"]["in_stock"] is True


async def test_order_comments_customer_and_staff(client, db):
    tomato, _ = await shop(db)
    buyer = await register(client)
    stranger = await register(client, "stranger@test.ru")
    manager = await staff(client, db, SystemRole.MANAGER, "m-c@test.ru")
    picker = await staff(client, db, SystemRole.PICKER, "p-c@test.ru")
    order = (await client.post("/api/v1/me/orders", headers=buyer, json=checkout_body((tomato, 1)))).json()
    url = f"/api/v1/me/orders/{order['id']}/comments"

    r = await client.post(url, headers=buyer, json={"text": "Позвоните за 30 минут, пожалуйста"})
    assert r.status_code == 201 and r.json()[0]["author"] == "Мария Кузнецова"
    assert (await client.get(url, headers=stranger)).status_code == 404  # чужой заказ
    assert (
        await client.post(f"/api/v1/admin/orders/{order['id']}/comments", headers=picker, json={"text": "x"})
    ).status_code == 403

    thread = (
        await client.post(
            f"/api/v1/admin/orders/{order['id']}/comments", headers=manager, json={"text": "Хорошо, позвоним!"}
        )
    ).json()
    assert [(c["from_staff"], c["author"]) for c in thread] == [(False, "Мария Кузнецова"), (True, "Магазин")]
    assert len((await client.get(url, headers=buyer)).json()) == 2

    await client.patch(f"/api/v1/staff/orders/{order['id']}/status", headers=manager, json={"status": "cancelled"})
    assert (await client.post(url, headers=buyer, json={"text": "ещё"})).status_code == 409  # закрытый заказ
    assert (await client.post(url, headers=buyer, json={"text": ""})).status_code == 422
