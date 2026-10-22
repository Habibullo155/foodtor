import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.exception_handlers import http_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from sqlalchemy import text
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.middleware.gzip import GZipMiddleware

from app.api.v1 import (
    account,
    admin,
    admin_merch,
    admin_products,
    auth,
    b2b,
    catalog,
    courier,
    delivery,
    orders,
    payments,
    stories,
)
from app.core import errors_ru
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.db.session import SessionFactory
from app.services.bootstrap import ensure_system_roles
from app.web import routes as web_routes
from app.web.session_cookie import WebSessionCookieMiddleware

SHOP_CSP = (
    "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob: https:; "
    "connect-src 'self'; font-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; "
    "form-action 'self'; upgrade-insecure-requests"
)
# Локальное демо: Flutter-админка на /admin — как на домене админки в проде (wasm CanvasKit, шрифты, плитки карты)
ADMIN_CSP = (
    "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob: https:; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self' https:; "
    "worker-src 'self' blob:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
)

log = logging.getLogger("shop")


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Системные роли нужны до первого входа/регистрации; идемпотентно
    try:
        async with SessionFactory() as session, session.begin():
            await ensure_system_roles(session)
    except Exception:  # БД ещё не готова — healthcheck покажет, контейнер перезапустится
        log.exception("Bootstrap failed")
    yield


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="FOODTOR API",
        version="1.0.0",
        # В проде документация закрыта — меньше поверхность атаки
        docs_url=None if settings.is_prod else "/docs",
        redoc_url=None,
        openapi_url=None if settings.is_prod else "/openapi.json",
        lifespan=lifespan,
    )

    app.state.limiter = limiter

    async def rate_limited(request, exc: RateLimitExceeded):
        response = _rate_limit_exceeded_handler(request, exc)  # заголовки Retry-After/X-RateLimit — от slowapi
        return JSONResponse(
            {"detail": "Слишком много запросов — подождите минуту и попробуйте снова"},
            status_code=429,
            headers=dict(response.headers),
        )

    app.add_exception_handler(RateLimitExceeded, rate_limited)
    app.add_middleware(SlowAPIMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,  # никаких "*" вместе с credentials
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "X-Session"],
    )

    app.add_middleware(WebSessionCookieMiddleware)
    if settings.is_prod:
        # Подменённый Host не попадёт ни в canonical/sitemap, ни в письма: запросы на чужие домены — 400
        app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.allowed_hosts)

    @app.middleware("http")
    async def security_headers(request, call_next):
        response = await call_next(request)
        h = response.headers
        h.setdefault("X-Content-Type-Options", "nosniff")
        h.setdefault("X-Frame-Options", "DENY")
        if h.get("content-type", "").startswith("text/html"):
            # Страницы сайта: только свои скрипты/стили (никаких inline), плитки карты OSM, фото по https
            h.setdefault("Content-Security-Policy", ADMIN_CSP if request.url.path.startswith("/admin") else SHOP_CSP)
            h.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")  # OSM требует Referer для плиток
            h.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=(self)")
            h.setdefault("Cache-Control", "no-cache")
            h.setdefault("Cross-Origin-Opener-Policy", "same-origin")
        else:
            h.setdefault("Referrer-Policy", "no-referrer")
        if request.url.path.startswith("/static/"):
            # С версией в адресе — кэш на год; без версии (модули, импортируемые из JS) — каждый раз сверка по ETag,
            # иначе после релиза браузер мог бы взять старый код из кэша
            h["Cache-Control"] = "public, max-age=31536000, immutable" if request.query_params.get("v") else "no-cache"
        if settings.is_prod:
            h.setdefault("Strict-Transport-Security", "max-age=63072000; includeSubDomains")
        return response

    # Сжатие только статики: без Caddy (сервер на своём компьютере) админка весит ~4 МБ вместо ~1 МБ.
    # HTML и API не сжимаем здесь — там могут быть токены (атака BREACH), а перед продом сжимает Caddy
    app.mount("/static", GZipMiddleware(StaticFiles(directory=web_routes.STATIC)), name="static")
    if settings.admin_static_dir:  # локальное демо: Flutter-админка на том же адресе (/admin), без CORS
        app.mount("/admin", GZipMiddleware(StaticFiles(directory=settings.admin_static_dir, html=True)), name="admin")

    @app.exception_handler(StarletteHTTPException)
    async def http_errors(request, exc):
        # Человеческая 404 для страниц сайта; API — JSON, текст ошибки по-русски
        if exc.status_code == 404 and not request.url.path.startswith(("/api/", "/static/", "/media/")):
            return await web_routes.not_found_page(request)
        if isinstance(exc.detail, str):
            exc.detail = errors_ru.translate(exc.detail)
        return await http_exception_handler(request, exc)

    @app.exception_handler(RequestValidationError)
    async def validation_errors(request, exc: RequestValidationError):
        # Формат прежний (detail — список), но msg — по-русски и с названием поля: «Телефон: неверный формат»
        detail = [{"loc": e.get("loc"), "type": e.get("type"), "msg": errors_ru.field_error(e)} for e in exc.errors()]
        return JSONResponse({"detail": detail}, status_code=422)

    for router in (
        auth.router,
        account.router,
        courier.router,
        delivery.router,
        catalog.router,
        catalog.categories_router,
        orders.router,
        payments.router,
        admin.router,
        admin_products.router,
        admin_merch.router,
        b2b.router,
        stories.router,
    ):
        app.include_router(router, prefix="/api/v1")
    app.include_router(web_routes.router)

    # В проде /media обычно отдаёт Caddy (общий volume); локально и без Caddy — сам API
    if not settings.is_prod or settings.serve_media:
        Path(settings.media_root).mkdir(parents=True, exist_ok=True)
        app.mount(settings.media_url, StaticFiles(directory=settings.media_root), name="media")

    @app.get("/health", include_in_schema=False)
    async def health():
        try:
            async with SessionFactory() as session:
                await session.execute(text("SELECT 1"))
        except Exception:
            return JSONResponse({"status": "db_unavailable"}, status_code=503)
        return {"status": "ok"}

    return app


app = create_app()
