from decimal import Decimal

from app.models import SystemRole
from app.services.shop_info import WorkHours
from tests import factories as f
from tests.test_release_flows import staff


def test_hours_text():
    assert WorkHours((0, 1, 2, 3, 4, 5), "10:00", "22:00").text == "Пн–Сб с 10:00 до 22:00"
    assert WorkHours(tuple(range(7)), "09:00", "21:00").text == "ежедневно с 09:00 до 21:00"
    assert WorkHours((0, 1, 3, 4, 6), "10:00", "22:00").days_text == "Пн, Вт, Чт, Пт, Вс"
    assert WorkHours((0, 1, 2, 3, 4, 5), "10:00", "22:00").days_off == ["воскресенье"]


async def test_default_hours_on_site_and_delivery_payment_pages(client, db):
    home = await client.get("/")
    assert "Доставка Пн–Сб с 10:00 до 22:00" in home.text
    assert (await client.get("/api/v1/shop/options")).json()["hours"] == "Пн–Сб с 10:00 до 22:00"

    delivery = await client.get("/info/delivery")
    assert "Пн–Сб с 10:00 до 22:00" in delivery.text and "воскресенье — выходной" in delivery.text
    payment = await client.get("/info/payment")
    assert payment.status_code == 200 and "Наличными" in payment.text and "Банковской картой" in payment.text
    assert "онлайн" not in payment.text.lower()  # эквайринг не подключён — о нём ни слова
    assert 'value="card_online"' not in (await client.get("/checkout")).text


async def test_admin_changes_hours(client, db):
    owner = await staff(client, db, SystemRole.OWNER, "owner-hours@test.ru")
    manager = await staff(client, db, SystemRole.MANAGER, "manager-hours@test.ru")
    url = "/api/v1/admin/settings/hours"
    assert (await client.get(url, headers=owner)).json() == {
        "days": [0, 1, 2, 3, 4, 5],
        "start": "10:00",
        "end": "22:00",
        "text": "Пн–Сб с 10:00 до 22:00",
    }
    assert (await client.put(url, headers=manager, json={"days": [0], "start": "10:00", "end": "22:00"})).status_code == 403
    late = await client.put(url, headers=owner, json={"days": [0], "start": "22:00", "end": "10:00"})
    assert late.status_code == 422 and "позже открытия" in late.text
    assert (await client.put(url, headers=owner, json={"days": [0], "start": "25:00", "end": "26:00"})).status_code == 422

    r = await client.put(url, headers=owner, json={"days": [6, 5, 4, 3, 2, 1, 0], "start": "09:00", "end": "21:00"})
    assert r.json()["text"] == "ежедневно с 09:00 до 21:00"
    assert "Доставка ежедневно с 09:00 до 21:00" in (await client.get("/")).text


async def test_promo_and_business_pages(client, db):
    veg = await f.category(db, "Овощи")
    small = await f.product(db, "Морковь", "90", cat=veg)
    small.compare_at_price = Decimal("100")
    big = await f.product(db, "Клубника", "300", cat=veg)
    big.compare_at_price = Decimal("500")
    await f.product(db, "Лук", "50", cat=veg)
    await db.commit()

    promo = await client.get("/promo")
    assert promo.status_code == 200 and "Лук" not in promo.text
    assert promo.text.index("Клубника") < promo.text.index("Морковь")  # самая большая скидка — первой
    assert 'href="/promo"' in (await client.get("/")).text

    business = await client.get("/business")
    assert business.status_code == 200 and "data-b2b-form" in business.text and "business-page.js" in business.text
    sitemap = (await client.get("/sitemap.xml")).text
    assert "/promo</loc>" in sitemap and "/business</loc>" in sitemap and "/info/payment</loc>" in sitemap


def test_social_links_are_normalized():
    from app.services.shop_info import instagram_url, telegram_url

    assert telegram_url("@foodtor_shop") == "https://t.me/foodtor_shop"
    assert telegram_url("https://t.me/foodtor_shop/") == "https://t.me/foodtor_shop"
    assert instagram_url("www.instagram.com/foodtor.shop/?igsh=abc") == "https://instagram.com/foodtor.shop"
    assert telegram_url("  ") == ""
    for bad in ("https://evil.ru/foodtor", "t.me/abc", "javascript:alert(1)"):
        try:
            telegram_url(bad)
        except ValueError:
            continue
        raise AssertionError(bad)


async def test_admin_sets_socials_and_site_shows_them(client, db):
    owner = await staff(client, db, SystemRole.OWNER, "owner-soc@test.ru")
    url = "/api/v1/admin/settings/socials"
    home = (await client.get("/")).text
    assert "i-telegram" not in home and '"openingHours": ["Mo-Sa 10:00-22:00"]' in home

    bad = await client.put(url, headers=owner, json={"telegram": "https://evil.ru/x", "instagram": ""})
    assert bad.status_code == 422 and "Telegram" in bad.text
    r = await client.put(url, headers=owner, json={"telegram": "@foodtor_shop", "instagram": "instagram.com/foodtor"})
    assert r.json() == {"telegram": "https://t.me/foodtor_shop", "instagram": "https://instagram.com/foodtor"}
    assert (await client.get(url, headers=owner)).json() == r.json()

    home = (await client.get("/")).text
    assert 'href="https://t.me/foodtor_shop"' in home and "Instagram*" in home
    assert "признанной экстремистской" in home
    assert '"sameAs": ["https://t.me/foodtor_shop", "https://instagram.com/foodtor"]' in home
    contacts = (await client.get("/info/contacts")).text
    assert "t.me/foodtor_shop" in contacts
    options = (await client.get("/api/v1/shop/options")).json()
    assert options["telegram"] == "https://t.me/foodtor_shop"
