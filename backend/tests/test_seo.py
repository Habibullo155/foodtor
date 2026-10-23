from app.models import SystemRole
from app.services import shop_info
from app.services.geo import get_settings_row
from tests import factories as f
from tests.test_release_flows import staff


async def test_category_text_meta_and_verification(client, db):
    fruit = await f.category(db, "Фрукты")
    fruit.slug = "frukty"
    fruit.description = "Свежие фрукты с доставкой на дом: яблоки, груши и бананы.\nВторой абзац."
    fruit.image_url = "/static/catalog/c/frukty.webp"
    apple = await f.product(db, "Яблоки Гала", cat=fruit)
    row = await get_settings_row(db)
    row.yandex_verification = "abc123"
    await db.commit()
    shop_info.reset()

    page = (await client.get("/catalog/frukty")).text
    assert "<title>Фрукты — купить с доставкой по Москве | " in page
    assert '<meta name="description" content="Свежие фрукты с доставкой на дом: яблоки, груши и бананы. Второй' in page
    assert '<p>Второй абзац.</p>' in page and "Фрукты с доставкой по Москве</h2>" in page
    assert 'og:image" content="http://test/static/catalog/c/frukty.webp"' in page
    assert '<meta name="yandex-verification" content="abc123">' in page

    home = (await client.get("/")).text
    assert "static/catalog/og.jpg" in home and "доставка фруктов и овощей по Москве" in home

    product = (await client.get(f"/product/{apple.id}", follow_redirects=True)).text
    assert "с доставкой на дом по Москве" in product
    assert '"brand"' not in product.split("application/ld+json")[1].split("</script>")[0]

    sitemap = (await client.get("/sitemap.xml")).text
    assert "<image:loc>http://test/static/catalog/c/frukty.webp</image:loc>" in sitemap
    assert "Clean-param: ref&utm_source" in (await client.get("/robots.txt")).text


async def test_seo_settings_validated(client, db):
    owner = await staff(client, db, SystemRole.OWNER, "owner-seo@test.ru")
    body = (await client.get("/api/v1/admin/settings/shop", headers=owner)).json()
    assert body["delivery_area"] == "по Москве"
    bad = {**body, "yandex_verification": '"><script>'}
    assert (await client.put("/api/v1/admin/settings/shop", json=bad, headers=owner)).status_code == 422
    ok = {**body, "delivery_area": "по Москве и области", "google_verification": "G-code_1"}
    assert (await client.put("/api/v1/admin/settings/shop", json=ok, headers=owner)).status_code == 200
