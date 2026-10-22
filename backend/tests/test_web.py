import json
import re

from tests import factories as f
from tests.test_release_flows import PW, register


async def _shop(db):
    veg = await f.category(db, "Овощи")
    veg.slug = "ovoschi"
    tomato = await f.product(db, "Томаты розовые", "249", cat=veg, stock=10)
    tomato.description = "Сладкие розовые томаты"
    await f.product(db, "Огурцы <script>alert(1)</script>", "189", cat=veg, stock=3)
    await db.commit()
    return veg, tomato


def _ld(html: str) -> list[dict]:
    return [json.loads(m) for m in re.findall(r'<script type="application/ld\+json">(.*?)</script>', html, re.S)]


async def test_pages_render_with_seo(client, db):
    veg, tomato = await _shop(db)
    home = await client.get("/")
    assert home.status_code == 200 and "Томаты розовые" in home.text
    assert '<link rel="canonical" href="http://test/">' in home.text and 'name="description"' in home.text
    assert "noindex" not in home.text

    cat = await client.get("/catalog/ovoschi")
    assert cat.status_code == 200 and "<h1>Овощи" in cat.text
    filtered = await client.get("/catalog/ovoschi?sort=price_asc&in_stock=true")
    assert 'name="robots" content="noindex, follow"' in filtered.text  # варианты фильтров не индексируем
    assert '<link rel="canonical" href="http://test/catalog/ovoschi">' in filtered.text
    assert (await client.get("/catalog/net-takoy")).status_code == 404

    # Товар: ЧПУ, редирект со старого адреса, микроразметка Product + хлебные крошки
    old = await client.get(f"/product/{tomato.id}", follow_redirects=False)
    assert old.status_code == 301 and old.headers["location"] == f"/product/{tomato.id}-tomaty-rozovye"
    page = await client.get(f"/product/{tomato.id}-tomaty-rozovye")
    assert page.status_code == 200 and "<title>Томаты розовые" in page.text
    product_ld, crumbs = _ld(page.text)
    assert product_ld["@type"] == "Product" and product_ld["offers"]["price"] == "249.00"
    assert product_ld["offers"]["availability"].endswith("InStock")
    assert crumbs["@type"] == "BreadcrumbList" and crumbs["itemListElement"][1]["name"] == "Овощи"


async def test_xss_in_product_name_is_escaped(client, db):
    await _shop(db)
    html = (await client.get("/catalog")).text
    assert "<script>alert(1)</script>" not in html
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in html
    # JSON в data-атрибуте карточки тоже экранирован (кавычки и угловые скобки)
    assert "\\u003cscript\\u003e" in html


async def test_service_pages_noindex_and_sitemap(client, db):
    veg, tomato = await _shop(db)
    for path in ("/cart", "/checkout", "/login", "/account", "/info/about"):
        r = await client.get(path)
        assert r.status_code == 200 and 'content="noindex, follow"' in r.text, path
    for path in ("/info/delivery", "/info/offer", "/info/privacy", "/info/returns", "/info/contacts"):
        assert (await client.get(path)).status_code == 200, path

    robots = (await client.get("/robots.txt")).text
    assert "Disallow: /account" in robots and "Sitemap: http://test/sitemap.xml" in robots
    sitemap = (await client.get("/sitemap.xml")).text
    assert "http://test/catalog/ovoschi" in sitemap and f"http://test/product/{tomato.id}-tomaty-rozovye" in sitemap

    nf = await client.get("/net-takoy-stranicy")
    assert nf.status_code == 404 and "Страница не найдена" in nf.text
    api404 = await client.get("/api/v1/net")
    assert api404.status_code == 404 and api404.headers["content-type"].startswith("application/json")


async def test_security_headers_on_pages(client, db):
    await _shop(db)
    r = await client.get("/")
    csp = r.headers["content-security-policy"]
    assert "script-src 'self'" in csp and "unsafe-inline" not in csp and "frame-ancestors 'none'" in csp
    assert r.headers["x-frame-options"] == "DENY" and r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["referrer-policy"] == "strict-origin-when-cross-origin"
    css = await client.get(re.search(r'href="(/static/css/shop\.css\?v=\w+)"', r.text).group(1))
    assert css.status_code == 200 and "immutable" in css.headers["cache-control"]
    # в HTML нет inline-скриптов (кроме JSON-LD) и inline-стилей — CSP их бы заблокировал
    html = (await client.get("/catalog")).text
    assert not re.search(r"<script(?![^>]*\bsrc=)(?![^>]*application/ld\+json)[^>]*>", html)
    assert " style=" not in html


async def test_web_session_cookie(client, db):
    await register(client, "web@test.ru")
    login = await client.post(
        "/api/v1/auth/login", data={"username": "web@test.ru", "password": PW}, headers={"X-Session": "cookie"}
    )
    assert login.status_code == 200
    assert "refresh_token" not in login.json() and login.json()["access_token"]  # refresh — только в cookie
    cookie = login.headers["set-cookie"]
    assert "rt=" in cookie and "HttpOnly" in cookie and "SameSite=strict" in cookie and "Path=/api/v1/auth" in cookie

    refreshed = await client.post("/api/v1/auth/refresh", headers={"X-Session": "cookie"})
    assert refreshed.status_code == 200 and refreshed.json()["access_token"]
    out = await client.post("/api/v1/auth/logout", headers={"X-Session": "cookie"}, json={})
    assert out.status_code == 204 and 'rt=""' in out.headers.get("set-cookie", "")
    client.cookies.clear()
    assert (await client.post("/api/v1/auth/refresh", headers={"X-Session": "cookie"})).status_code == 401

    # мобильный/Flutter-клиент без заголовка — как раньше, токен в теле
    plain = await client.post("/api/v1/auth/login", data={"username": "web@test.ru", "password": PW})
    assert plain.json()["refresh_token"] and "set-cookie" not in plain.headers


async def test_shop_options_public(client):
    r = (await client.get("/api/v1/shop/options")).json()
    assert r["online_payment"] is False and r["free_courier_from"] == 1500


async def test_seo_details(client, db):
    veg, tomato = await _shop(db)
    for i in range(30):  # > 24 на странице → пагинация
        await f.product(db, f"Капуста {i}", "50", cat=veg, stock=5)
    await db.commit()
    home = (await client.get("/")).text
    types = {d["@type"] for d in _ld(home)}
    assert {"GroceryStore", "WebSite"} <= types
    assert 'property="og:type" content="website"' in home

    p2 = (await client.get("/catalog/ovoschi?page=2")).text
    assert '<link rel="canonical" href="http://test/catalog/ovoschi?page=2">' in p2  # самостоятельная страница
    assert '<link rel="prev" href="http://test/catalog/ovoschi">' in p2 and "noindex" not in p2
    assert "страница 2" in p2.split("</title>")[0]

    prod = (await client.get(f"/product/{tomato.id}-tomaty-rozovye")).text
    assert 'property="og:type" content="product"' in prod and 'rel="preload" as="image"' in prod
    assert 'alt="Томаты розовые' in prod
    sitemap = (await client.get("/sitemap.xml")).text
    assert "<lastmod>" in sitemap and "<priority>1.0</priority>" in sitemap
