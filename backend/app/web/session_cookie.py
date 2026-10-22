"""Сайт хранит refresh-токен не в JS, а в HttpOnly-cookie: даже XSS не сможет его украсть.

Клиент сайта шлёт заголовок «X-Session: cookie». Тогда в ответах /api/v1/auth/* refresh-токен вырезается
из JSON и ставится cookie: HttpOnly, SameSite=Strict, Path=/api/v1/auth (в остальные запросы не уходит),
Secure — на https. Мобильные/Flutter-клиенты без заголовка работают как раньше (токен в теле).
"""

import json

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.api.v1.auth import REFRESH_COOKIE
from app.core.config import get_settings

COOKIE_PATH = "/api/v1/auth"


class WebSessionCookieMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        if not request.url.path.startswith(COOKIE_PATH) or request.headers.get("x-session") != "cookie":
            return response
        secure = request.url.scheme == "https" or get_settings().is_prod
        refresh = getattr(request.state, "issued_refresh", None)
        if (
            refresh
            and response.status_code < 300
            and response.headers.get("content-type", "").startswith("application/json")
        ):
            body = b"".join([chunk async for chunk in response.body_iterator])
            data = json.loads(body)
            data.pop("refresh_token", None)
            headers = {k: v for k, v in response.headers.items() if k.lower() != "content-length"}
            response = Response(
                json.dumps(data, ensure_ascii=False),
                status_code=response.status_code,
                headers=headers,
                media_type="application/json",
            )
            response.set_cookie(
                REFRESH_COOKIE,
                refresh,
                max_age=get_settings().refresh_token_ttl_days * 86400,
                path=COOKIE_PATH,
                httponly=True,
                secure=secure,
                samesite="strict",
            )
        elif getattr(request.state, "clear_refresh_cookie", False) or (
            request.url.path.endswith("/refresh") and response.status_code == 401
        ):
            response.delete_cookie(REFRESH_COOKIE, path=COOKIE_PATH, httponly=True, secure=secure, samesite="strict")
        return response
