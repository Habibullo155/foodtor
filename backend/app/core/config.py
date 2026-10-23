from functools import lru_cache

from pydantic import SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "dev"
    database_url: str
    # Счётчики rate limit и блокировок входа. Пусто — в памяти процесса (хватает для одного воркера)
    redis_url: str | None = None

    jwt_secret: SecretStr
    jwt_algorithm: str = "HS256"
    access_token_ttl_min: int = 15
    refresh_token_ttl_days: int = 30

    cors_origins: list[str] = []
    max_import_file_mb: int = 10

    # Название витрины. Контакты, доставка и реквизиты — в админке («Магазин и доставка»)
    shop_name: str = "FOODTOR"

    # Публичные адреса (нужны для returnUrl оплаты и ссылок в письмах)
    public_shop_url: str = "http://localhost:8765"
    public_api_url: str = "http://localhost:8000"
    extra_hosts: list[str] = []  # домен админки и т.п. — к ним тоже разрешены запросы (TrustedHost)

    # Загруженные файлы (аватары). В проде — общий volume с Caddy, который отдаёт /media/*
    media_root: str = "media"
    media_url: str = "/media"
    serve_media: bool = False  # в проде без Caddy (сервер на своём компьютере) фото отдаёт сам API
    # Только для локального демо: путь к собранной Flutter-админке → отдаётся на /admin того же сервера
    admin_static_dir: str | None = None

    # Геокодер для зоны доставки: по умолчанию OpenStreetMap Nominatim (бесплатно, ≤1 запрос/с),
    # с ключом — Яндекс Геокодер (точнее по адресам РФ). https://developer.tech.yandex.ru
    yandex_geocoder_key: SecretStr | None = None
    geocoder_contact_email: str = ""  # контакт для Nominatim (их правила); адреса @example.* Nominatim блокирует

    # Часовой пояс магазина: дни в отчётах и «сегодня» — по местному времени, не по UTC
    timezone: str = "Europe/Moscow"

    # Альфа-Банк, интернет-эквайринг (REST). Тестовый стенд по умолчанию; боевой — https://pay.alfabank.ru/payment/rest
    alfa_api_url: str = "https://alfa.rbsuat.com/payment/rest"
    alfa_username: str | None = None
    alfa_password: SecretStr | None = None

    # SMS-коды для входа по телефону. smsru — https://sms.ru (api_id из личного кабинета);
    # console — код пишется в лог сервера (только для разработки, в проде отправка отключена).
    sms_provider: str = "console"
    smsru_api_id: SecretStr | None = None
    sms_sender: str | None = None  # имя отправителя, если согласовано в SMS.ru

    # Письма с кодом входа (SMTP вашей почты: Яндекс 360, Mail.ru для бизнеса, Unisender Go и т.п.).
    # Пусто — в разработке код пишется в лог, в проде вход по коду на email отключён (пароль работает).
    smtp_host: str | None = None
    smtp_port: int = 465
    smtp_user: str | None = None
    smtp_password: SecretStr | None = None
    smtp_from: str | None = None  # «Магазин <noreply@shop.ru>»; по умолчанию — smtp_user
    smtp_security: str = "ssl"  # ssl (порт 465) | starttls (порт 587)

    @model_validator(mode="after")
    def _prod_is_safe(self):
        """В проде не стартуем с небезопасными настройками — лучше упасть при запуске, чем работать с дырой."""
        if self.app_env != "prod":
            return self
        problems = []
        if len(self.jwt_secret.get_secret_value()) < 32:
            problems.append("JWT_SECRET короче 32 символов (сгенерируйте: openssl rand -base64 48)")
        for name in ("public_shop_url", "public_api_url"):
            if not getattr(self, name).startswith("https://"):
                problems.append(f"{name.upper()} должен начинаться с https://")
        if "*" in self.cors_origins:
            problems.append("CORS_ORIGINS не может содержать «*»")
        if problems:
            raise ValueError("Небезопасные настройки для прода: " + "; ".join(problems))
        return self

    @property
    def allowed_hosts(self) -> list[str]:
        """Домены, на которые отвечает сервер (защита от подмены заголовка Host)."""
        from urllib.parse import urlparse

        hosts = {urlparse(u).hostname for u in (self.public_shop_url, self.public_api_url)}
        # EXTRA_HOSTS — голые домены («admin.shop.ru», «*.lhr.life»), а не адреса со схемой
        hosts |= {h.strip().lower() for h in self.extra_hosts}
        return sorted(h for h in hosts if h) + ["api", "localhost", "127.0.0.1"]  # api — имя контейнера для healthcheck

    @property
    def sms_enabled(self) -> bool:
        return (
            self.sms_provider == "smsru"
            and self.smsru_api_id is not None
            or (self.sms_provider == "console" and not self.is_prod)
        )

    @property
    def payments_enabled(self) -> bool:
        return bool(self.alfa_username and self.alfa_password)

    @property
    def use_redis(self) -> bool:
        return self.is_prod and bool(self.redis_url)

    @property
    def is_prod(self) -> bool:
        return self.app_env == "prod"


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
