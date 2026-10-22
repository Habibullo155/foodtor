"""Rate limiting (slowapi). В проде с REDIS_URL счётчики общие для всех воркеров, иначе — в памяти процесса."""

from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import get_settings

_settings = get_settings()

limiter = Limiter(
    key_func=get_remote_address,  # за reverse-proxy включите uvicorn --proxy-headers
    default_limits=["300/minute"],  # с запасом: за CGNAT мобильных операторов один IP у многих людей
    storage_uri=_settings.redis_url if _settings.use_redis else "memory://",
)

# Жёсткие лимиты для чувствительных эндпоинтов (брутфорс паролей)
AUTH_LIMIT = "5/minute"
IMPORT_LIMIT = "10/hour"
