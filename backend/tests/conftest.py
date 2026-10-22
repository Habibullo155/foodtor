"""
Интеграционные тесты (`db`, `client`) идут на настоящем PostgreSQL 16:
локально — через pip-пакет pgserver (без Docker), в CI — через сервис postgres
(переменная TEST_DATABASE_URL). Если ни то ни другое недоступно — интеграционные тесты пропускаются.
"""

import os
import tempfile

import pytest

os.environ.setdefault("APP_ENV", "test")
os.environ.setdefault("JWT_SECRET", "test-secret-test-secret-test-secret-test-secret")

_pg = None
if url := os.getenv("TEST_DATABASE_URL"):
    os.environ["DATABASE_URL"] = url
else:
    try:
        import pgserver

        _pg = pgserver.get_server(tempfile.mkdtemp(prefix="shop-pg-"), cleanup_mode="stop")
        sock = _pg.get_uri().split("host=")[1]
        os.environ["DATABASE_URL"] = f"postgresql+asyncpg://postgres@/postgres?host={sock}"
    except Exception:  # pgserver не установлен — только юнит-тесты
        os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://unused@localhost/unused")

INTEGRATION = bool(os.getenv("TEST_DATABASE_URL")) or _pg is not None


def pytest_sessionfinish(session, exitstatus):
    if _pg is not None:
        _pg.cleanup()


@pytest.fixture(scope="session")
def _schema():
    if not INTEGRATION:
        pytest.skip("PostgreSQL недоступен: pip install pgserver или TEST_DATABASE_URL")
    import asyncio

    import app.models  # noqa: F401
    from app.db.base import Base
    from app.db.session import engine

    # pg_trgm есть в продовом postgres (миграция создаёт расширение), но не в pgserver
    products = Base.metadata.tables["products"]
    products.indexes = {i for i in products.indexes if "trgm" not in i.name}

    async def create():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)

    asyncio.run(create())


@pytest.fixture
async def db(_schema):
    """Чистая БД на каждый тест (TRUNCATE всех таблиц) + сессия."""
    from sqlalchemy import text

    from app.db.base import Base
    from app.db.session import SessionFactory

    async with SessionFactory() as s:
        tables = ", ".join(t.name for t in Base.metadata.sorted_tables)
        await s.execute(text(f"TRUNCATE {tables} RESTART IDENTITY CASCADE"))
        await s.commit()
        yield s


@pytest.fixture
async def client(db):
    import httpx

    from app.core import login_guard
    from app.core.rate_limit import limiter
    from app.main import app
    from app.services import shop_info

    limiter.reset()  # счётчики rate limit не переносятся между тестами
    login_guard.reset_all()
    shop_info.reset()

    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


# Геокодер в тестах без внешних запросов:
# «Москва …» → около центра; «Тула …» → 170 км; «Химки …» → ~19 км; прочее — не найдено.
FAKE_PLACES = {"москва": (55.7558, 37.6176), "химки": (55.8897, 37.4450), "тула": (54.1931, 37.6177)}


@pytest.fixture(autouse=True)
def fake_geocoder(monkeypatch):
    import httpx

    from app.services import geo

    def handler(request: httpx.Request):
        if request.url.path.endswith("/reverse"):  # точка → ближайший «город» из списка
            lat, lng = float(request.url.params["lat"]), float(request.url.params["lon"])
            name, _ = min(FAKE_PLACES.items(), key=lambda kv: (kv[1][0] - lat) ** 2 + (kv[1][1] - lng) ** 2)
            return httpx.Response(
                200, json={"address": {"city": name.title(), "road": "Тестовая улица", "house_number": "1"}}
            )
        q = request.url.params.get("q", "").lower()
        for name, (lat, lng) in FAKE_PLACES.items():
            if name in q:
                # дом «нашёлся», только если в запросе есть номер (как у Nominatim с addressdetails)
                house = {"house_number": "1"} if any(ch.isdigit() for ch in q) else {}
                return httpx.Response(200, json=[{"lat": str(lat), "lon": str(lng), "address": house}])
        return httpx.Response(200, json=[])

    geo._memo.clear()
    geo._reverse_memo.clear()
    monkeypatch.setattr(geo, "TEST_TRANSPORT", httpx.MockTransport(handler))
