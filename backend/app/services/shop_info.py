import re
import time
from dataclasses import dataclass, field
from decimal import Decimal

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import DeliveryMethod
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
class Contacts:
    phone: str = "+7 (985) 394-72-62"
    email: str = ""

    @property
    def tel(self) -> str:
        """Для ссылки tel:… — только «+» и цифры."""
        return "+" + re.sub(r"\D", "", self.phone).lstrip("+")


@dataclass(frozen=True, slots=True)
class DeliveryRules:
    min_order: Decimal = Decimal("2500")
    courier_fee: Decimal = Decimal("199")
    free_from: Decimal | None = Decimal("5000")  # None — курьер всегда платный
    express_enabled: bool = True
    express_fee: Decimal = Decimal("349")
    express_hours: int = 2
    pickup_enabled: bool = True

    def fee(self, method: DeliveryMethod, goods: Decimal) -> Decimal:
        match method:
            case DeliveryMethod.EXPRESS:
                return self.express_fee
            case DeliveryMethod.COURIER:
                return Decimal(0) if self.free_from is not None and goods >= self.free_from else self.courier_fee
            case DeliveryMethod.PICKUP:
                return Decimal(0)

    def problem(self, method: DeliveryMethod, goods: Decimal) -> str | None:
        """Почему заказ с такой суммой и способом нельзя оформить (None — можно)."""
        if method is DeliveryMethod.EXPRESS and not self.express_enabled:
            return "Экспресс-доставка сейчас недоступна — выберите курьера"
        if method is DeliveryMethod.PICKUP and not self.pickup_enabled:
            return "Самовывоз сейчас недоступен — выберите доставку"
        if method is not DeliveryMethod.PICKUP and goods < self.min_order:
            return f"Доставка — при заказе от {self.min_order:.0f} ₽. Добавьте товаров ещё на {self.min_order - goods:.0f} ₽"
        return None

    @property
    def express_label(self) -> str:
        h = self.express_hours
        return f"Экспресс за {h} {'час' if h == 1 else 'часа' if h < 5 else 'часов'}"


@dataclass(frozen=True, slots=True)
class ReferralRules:
    enabled: bool = True
    friend_amount: Decimal = Decimal("300")
    inviter_amount: Decimal = Decimal("300")
    min_order: Decimal = Decimal("2500")


@dataclass(frozen=True, slots=True)
class Legal:
    name: str = ""
    inn: str = ""
    ogrn: str = ""
    address: str = ""

    @property
    def filled(self) -> bool:
        return bool(self.name and self.inn)


@dataclass(frozen=True, slots=True)
class ShopInfo:
    hours: WorkHours
    socials: Socials = field(default_factory=Socials)
    contacts: Contacts = field(default_factory=Contacts)
    delivery: DeliveryRules = field(default_factory=DeliveryRules)
    referral: ReferralRules = field(default_factory=ReferralRules)
    legal: Legal = field(default_factory=Legal)


DEFAULT = ShopInfo(WorkHours((0, 1, 2, 3, 4, 5), "10:00", "22:00"))

# Страницы сайта рендерятся синхронно: держим настройки магазина в памяти и перечитываем раз в минуту —
# правка в админке доходит до всех воркеров без перезапуска.
_cache: tuple[float, ShopInfo] = (0.0, DEFAULT)
TTL = 60.0


def from_row(row) -> ShopInfo:
    return ShopInfo(
        hours=WorkHours(tuple(sorted(row.work_days or [])), row.work_from, row.work_to),
        socials=Socials(row.telegram_url or "", row.instagram_url or ""),
        contacts=Contacts(row.contact_phone, row.contact_email),
        delivery=DeliveryRules(
            min_order=row.delivery_min_order,
            courier_fee=row.courier_fee,
            free_from=row.free_delivery_from,
            express_enabled=row.express_enabled,
            express_fee=row.express_fee,
            express_hours=row.express_hours,
            pickup_enabled=row.pickup_enabled,
        ),
        referral=ReferralRules(
            row.referral_enabled, row.referral_friend_amount, row.referral_inviter_amount, row.referral_min_order
        ),
        legal=Legal(row.legal_name, row.legal_inn, row.legal_ogrn, row.legal_address),
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
