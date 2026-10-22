import re
import time
from dataclasses import dataclass, field

from sqlalchemy.ext.asyncio import AsyncSession

from app.services.geo import get_settings_row

DAY_SHORT = ("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс")


@dataclass(frozen=True, slots=True)
class WorkHours:
    days: tuple[int, ...]
    start: str
    end: str

    @property
    def days_text(self) -> str:
        if len(self.days) == 7:
            return "ежедневно"
        runs: list[list[int]] = []
        for d in sorted(self.days):
            if runs and d == runs[-1][-1] + 1:
                runs[-1].append(d)
            else:
                runs.append([d])
        parts = [
            DAY_SHORT[r[0]] if len(r) == 1 else f"{DAY_SHORT[r[0]]}{'–' if len(r) > 2 else ', '}{DAY_SHORT[r[-1]]}"
            for r in runs
        ]
        return ", ".join(parts)

    @property
    def time_text(self) -> str:
        return f"с {self.start} до {self.end}"

    @property
    def text(self) -> str:
        return f"{self.days_text} {self.time_text}" if self.days else "временно не работаем"

    @property
    def schema(self) -> list[str]:
        """openingHours для schema.org: ["Mo-Sa 10:00-22:00"]."""
        codes = ("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su")
        days = sorted(self.days)
        if not days:
            return []
        span = f"{codes[days[0]]}-{codes[days[-1]]}" if days == list(range(days[0], days[-1] + 1)) else ",".join(
            codes[d] for d in days
        )
        return [f"{span} {self.start}-{self.end}"]

    @property
    def days_off(self) -> list[str]:
        names = ("понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье")
        return [names[d] for d in range(7) if d not in self.days]


TELEGRAM = re.compile(r"^(?:https?://)?(?:www\.)?(?:t|telegram)\.me/([A-Za-z0-9_]{5,32})/?$|^@?([A-Za-z0-9_]{5,32})$")
INSTAGRAM = re.compile(r"^(?:https?://)?(?:www\.)?instagram\.com/([A-Za-z0-9._]{1,30})/?(?:\?.*)?$|^@?([A-Za-z0-9._]{1,30})$")


def _account(value: str, pattern: re.Pattern[str]) -> str | None:
    m = pattern.match(value.strip())
    return (m.group(1) or m.group(2)) if m else None


def telegram_url(value: str) -> str:
    """«@foodtor», «t.me/foodtor», полная ссылка → https://t.me/foodtor; пусто — соцсеть не показываем."""
    if not value.strip():
        return ""
    if (name := _account(value, TELEGRAM)) is None:
        raise ValueError("Telegram: укажите ссылку t.me/… или @имя (от 5 латинских букв и цифр)")
    return f"https://t.me/{name}"


def instagram_url(value: str) -> str:
    if not value.strip():
        return ""
    if (name := _account(value, INSTAGRAM)) is None:
        raise ValueError("Instagram: укажите ссылку instagram.com/… или @имя")
    return f"https://instagram.com/{name}"


@dataclass(frozen=True, slots=True)
class Socials:
    telegram: str = ""
    instagram: str = ""

    @property
    def links(self) -> list[str]:
        return [u for u in (self.telegram, self.instagram) if u]


@dataclass(frozen=True, slots=True)
class ShopInfo:
    hours: WorkHours
    socials: Socials = field(default_factory=Socials)


DEFAULT = ShopInfo(WorkHours((0, 1, 2, 3, 4, 5), "10:00", "22:00"))

# Страницы сайта рендерятся синхронно: держим часы и соцсети в памяти и перечитываем раз в минуту —
# правка в админке доходит до всех воркеров без перезапуска.
_cache: tuple[float, ShopInfo] = (0.0, DEFAULT)
TTL = 60.0


def from_row(row) -> ShopInfo:
    return ShopInfo(
        WorkHours(tuple(sorted(row.work_days or [])), row.work_from, row.work_to),
        Socials(row.telegram_url or "", row.instagram_url or ""),
    )


async def load(session: AsyncSession) -> ShopInfo:
    global _cache
    if time.monotonic() - _cache[0] < TTL:
        return _cache[1]
    info = from_row(await get_settings_row(session))
    _cache = (time.monotonic(), info)
    return info


def remember(info: ShopInfo) -> None:
    global _cache
    _cache = (time.monotonic(), info)


def current() -> ShopInfo:
    return _cache[1]


def reset() -> None:
    global _cache
    _cache = (0.0, DEFAULT)
