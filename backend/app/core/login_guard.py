"""Защита от подбора пароля к конкретному аккаунту (в дополнение к лимиту по IP).

5 неудачных попыток за 15 минут → вход в этот email закрыт на 15 минут, даже с верным паролем
и с любых IP (ботнет не обойдёт). Счётчик ведётся по email независимо от того, существует ли
аккаунт, — поэтому блокировка не выдаёт, зарегистрирован ли адрес.
В проде с REDIS_URL счётчики в Redis (общие для всех воркеров), иначе — в памяти процесса.
"""

import hashlib
import time

from app.core.config import get_settings

MAX_FAILS = 5
WINDOW_S = 15 * 60
LOCK_S = 15 * 60


def _key(email: str) -> str:
    return hashlib.sha256(email.strip().lower().encode()).hexdigest()[:32]  # email в Redis не храним


class _MemoryStore:
    def __init__(self) -> None:
        self.fails: dict[str, tuple[int, float]] = {}
        self.locks: dict[str, float] = {}

    async def locked_for(self, k: str) -> int:
        return max(0, int(self.locks.get(k, 0) - time.monotonic()))

    async def fail(self, k: str) -> None:
        now = time.monotonic()
        n, since = self.fails.get(k, (0, now))
        if now - since > WINDOW_S:
            n, since = 0, now
        n += 1
        self.fails[k] = (n, since)
        if n >= MAX_FAILS:
            self.locks[k] = now + LOCK_S
            self.fails.pop(k, None)

    async def reset(self, k: str) -> None:
        self.fails.pop(k, None)


class _RedisStore:
    def __init__(self, url: str) -> None:
        from redis.asyncio import from_url

        self.r = from_url(url)

    async def locked_for(self, k: str) -> int:
        return max(0, int(await self.r.ttl(f"login:lock:{k}")))

    async def fail(self, k: str) -> None:
        n = await self.r.incr(f"login:fail:{k}")
        if n == 1:
            await self.r.expire(f"login:fail:{k}", WINDOW_S)
        if n >= MAX_FAILS:
            await self.r.set(f"login:lock:{k}", 1, ex=LOCK_S)
            await self.r.delete(f"login:fail:{k}")

    async def reset(self, k: str) -> None:
        await self.r.delete(f"login:fail:{k}")


_s = get_settings()
_store = _RedisStore(_s.redis_url) if _s.use_redis else _MemoryStore()


async def locked_for(email: str) -> int:
    """Сколько секунд ещё действует блокировка (0 — можно входить)."""
    return await _store.locked_for(_key(email))


async def register_failure(email: str) -> None:
    await _store.fail(_key(email))


async def register_success(email: str) -> None:
    await _store.reset(_key(email))


def reset_all() -> None:
    """Для тестов."""
    if isinstance(_store, _MemoryStore):
        _store.fails.clear()
        _store.locks.clear()
