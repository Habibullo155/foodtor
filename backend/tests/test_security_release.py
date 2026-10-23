import io

import pandas as pd
import pytest
from pydantic import ValidationError

from app.core.config import Settings, get_settings
from app.models import SystemRole
from app.services.import_export import _neutralize_formula
from app.web import routes
from tests import factories as f
from tests.test_release_flows import register, staff


def test_formula_injection_neutralized():
    assert _neutralize_formula('=HYPERLINK("http://evil","x")') == '\'=HYPERLINK("http://evil","x")'
    for bad in ("+1+1", "-2+3", "@SUM(A1)"):
        assert _neutralize_formula(bad).startswith("'")
    assert _neutralize_formula("Томаты") == "Томаты" and _neutralize_formula(42) == 42


async def test_export_has_no_live_formulas(client, db):
    veg = await f.category(db, "Овощи")
    await f.product(db, '=HYPERLINK("http://evil.ru","Скидка")', "100", cat=veg)
    await db.commit()
    owner = await staff(client, db, SystemRole.OWNER, "owner-exp@test.ru")
    r = await client.get("/api/v1/admin/products/export", params={"format": "csv"}, headers=owner)
    assert r.status_code == 200
    names = pd.read_csv(io.BytesIO(r.content))["Название"].tolist()
    assert names and all(not n.startswith("=") for n in names), names
    x = await client.get("/api/v1/admin/products/export", params={"format": "xlsx"}, headers=owner)
    assert x.status_code == 200
    assert all(not n.startswith("=") for n in pd.read_excel(io.BytesIO(x.content))["Название"])


def _settings(**kw):
    base = {
        "database_url": "postgresql+asyncpg://x/y",
        "jwt_secret": "s" * 48,
        "app_env": "prod",
        "public_shop_url": "https://shop.ru",
        "public_api_url": "https://shop.ru",
    }
    return Settings(_env_file=None, **(base | kw))


def test_prod_refuses_unsafe_settings():
    assert _settings().allowed_hosts[0] == "shop.ru"
    for bad in ({"jwt_secret": "short"}, {"public_shop_url": "http://shop.ru"}, {"cors_origins": ["*"]}):
        with pytest.raises(ValidationError, match="Небезопасные настройки"):
            _settings(**bad)
    Settings(_env_file=None, database_url="x", jwt_secret="short", app_env="dev")  # в разработке можно


async def test_seo_urls_use_configured_domain_in_prod(client, db, monkeypatch):
    s = get_settings()
    monkeypatch.setattr(s, "app_env", "prod")
    monkeypatch.setattr(s, "public_shop_url", "https://shop.ru")
    html = (await client.get("/info/delivery", headers={"Host": "evil.example"})).text
    assert '<link rel="canonical" href="https://shop.ru/info/delivery">' in html and "evil.example" not in html
    sitemap = (await client.get("/sitemap.xml", headers={"Host": "evil.example"})).text
    assert "https://shop.ru/" in sitemap and "evil.example" not in sitemap
    assert routes.site_base.__doc__  # canonical/sitemap/микроразметка берут адрес только отсюда


async def test_product_image_must_be_https(client, db):
    owner = await staff(client, db, SystemRole.OWNER, "owner-img2@test.ru")
    veg = await f.category(db, "Овощи")
    await db.commit()
    body = {"sku": "X-1", "name": "Тест", "retail_price": "10", "cost_price": "5", "category_id": veg.id}
    r = await client.post("/api/v1/admin/products", headers=owner, json=body | {"image_url": "http://evil.ru/x.png"})
    assert r.status_code == 422
    for bad in ("javascript:alert(1)", "data:image/png;base64,AAAA"):
        assert (
            await client.post("/api/v1/admin/products", headers=owner, json=body | {"image_url": bad})
        ).status_code == 422


async def test_quote_is_rate_limited(client, db):
    buyer = await register(client)
    veg = await f.category(db, "Овощи")
    p = await f.product(db, "Томаты", "100", cat=veg)
    await db.commit()
    codes = set()
    for _ in range(62):
        r = await client.post(
            "/api/v1/me/orders/quote",
            headers=buyer,
            json={"items": [{"product_id": p.id, "quantity": 1}], "promo_code": "GUESS"},
        )
        codes.add(r.status_code)
    assert 429 in codes  # перебор промокодов упирается в лимит


def test_extra_hosts_accept_bare_domains_and_wildcards():
    from app.core.config import Settings

    s = Settings(
        database_url="postgresql+asyncpg://x@/x",
        jwt_secret="x" * 40,
        public_shop_url="https://shop.ru",
        extra_hosts=["admin.shop.ru", "*.lhr.life"],
    )
    assert {"shop.ru", "admin.shop.ru", "*.lhr.life"} <= set(s.allowed_hosts)
