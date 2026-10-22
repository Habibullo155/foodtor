"""Одноразовые коды входа: SMS на телефон (SMS.ru) или письмо на email (SMTP).

Защита от перебора и «накрутки» отправок:
- телефон — только мобильные РФ (+79…); email — валидированный адрес в нижнем регистре;
- код 6 цифр, живёт 5 минут, 5 попыток ввода, хранится как HMAC;
- повторная отправка не раньше чем через 60 с, не больше 5 кодов в час на адрес и 10 в час с одного IP.
"""

import asyncio
import hashlib
import hmac
import logging
import re
import secrets
import smtplib
import ssl
from datetime import UTC, datetime, timedelta
from email.message import EmailMessage
from typing import Literal

import httpx
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import LoginCode

log = logging.getLogger("login_codes")

Channel = Literal["sms", "email"]

TEST_TRANSPORT: httpx.AsyncBaseTransport | None = None  # подмена SMS.ru в тестах
SENT_EMAILS: list[EmailMessage] | None = None  # тесты: письма складываются сюда вместо SMTP

CODE_TTL = timedelta(minutes=5)
RESEND_AFTER = timedelta(seconds=60)
MAX_ATTEMPTS = 5
MAX_PER_TARGET_HOUR = 5
MAX_PER_IP_HOUR = 10


class CodeError(Exception):

    def __init__(self, message: str, status: int = 400, retry_after: int | None = None):
        super().__init__(message)
        self.status = status
        self.retry_after = retry_after


def normalize_phone(raw: str) -> str | None:
    """«8 (916) 123-45-67», «+7 916…», «916…» → +79161234567. Не мобильный РФ → None."""
    digits = re.sub(r"\D", "", raw or "")
    if len(digits) == 10:
        digits = "7" + digits
    if len(digits) == 11 and digits[0] == "8":
        digits = "7" + digits[1:]
    if len(digits) != 11 or not digits.startswith("79"):
        return None
    return "+" + digits


def _hash(channel: str, target: str, code: str) -> str:
    key = get_settings().jwt_secret.get_secret_value().encode()
    return hmac.new(key, f"{channel}:{target}:{code}".encode(), hashlib.sha256).hexdigest()


async def issue_code(session: AsyncSession, channel: Channel, target: str, ip: str | None) -> tuple[str, int]:
    """Создаёт код и отправляет его. Возвращает (код, через сколько секунд можно повторить)."""
    now = datetime.now(UTC)
    same = (LoginCode.channel == channel, LoginCode.target == target)
    last = await session.scalar(select(LoginCode).where(*same).order_by(LoginCode.created_at.desc()).limit(1))
    if last and now - last.created_at < RESEND_AFTER:
        wait = int((RESEND_AFTER - (now - last.created_at)).total_seconds()) + 1
        raise CodeError(f"Новый код можно запросить через {wait} с", 429, wait)
    hour_ago = now - timedelta(hours=1)
    per_target = await session.scalar(
        select(func.count()).select_from(LoginCode).where(*same, LoginCode.created_at > hour_ago)
    )
    per_ip = (
        await session.scalar(
            select(func.count()).select_from(LoginCode).where(LoginCode.ip == ip, LoginCode.created_at > hour_ago)
        )
        if ip
        else 0
    )
    if per_target >= MAX_PER_TARGET_HOUR or per_ip >= MAX_PER_IP_HOUR:
        raise CodeError("Слишком много запросов кода. Попробуйте через час", 429, 3600)

    code = f"{secrets.randbelow(1_000_000):06d}"
    session.add(
        LoginCode(
            channel=channel, target=target, code_hash=_hash(channel, target, code), ip=ip, expires_at=now + CODE_TTL
        )
    )
    await session.flush()
    if channel == "sms":
        await send_sms(target, f"Код для входа в магазин: {code}. Никому его не сообщайте.")
    else:
        await send_email(
            target,
            f"Код для входа: {code}",
            f"Ваш код для входа в магазин: {code}\n\nОн действует 5 минут. Никому его не сообщайте — "
            "сотрудники магазина его не спрашивают.\n\nЕсли вы не запрашивали код, просто удалите это письмо.",
        )
    return code, int(RESEND_AFTER.total_seconds())


async def check_code(session: AsyncSession, channel: Channel, target: str, code: str) -> None:
    """Проверяет последний действующий код. Ошибка — CodeError с понятным текстом."""
    now = datetime.now(UTC)
    row = await session.scalar(
        select(LoginCode)
        .where(
            LoginCode.channel == channel,
            LoginCode.target == target,
            LoginCode.used_at.is_(None),
            LoginCode.expires_at > now,
        )
        .order_by(LoginCode.created_at.desc())
        .limit(1)
        .with_for_update()
    )
    if row is None:
        raise CodeError("Код устарел — запросите новый", 400)
    if row.attempts >= MAX_ATTEMPTS:
        raise CodeError("Слишком много неверных попыток — запросите новый код", 429)
    row.attempts += 1
    if not hmac.compare_digest(row.code_hash, _hash(channel, target, code.strip())):
        left = MAX_ATTEMPTS - row.attempts
        raise CodeError(f"Неверный код. Осталось попыток: {left}" if left else "Неверный код — запросите новый", 400)
    row.used_at = now


async def send_sms(phone: str, text: str) -> None:
    s = get_settings()
    if s.sms_provider == "smsru" and s.smsru_api_id:
        params = {"api_id": s.smsru_api_id.get_secret_value(), "to": phone.lstrip("+"), "msg": text, "json": 1}
        if s.sms_sender:
            params["from"] = s.sms_sender
        try:
            async with httpx.AsyncClient(timeout=10, transport=TEST_TRANSPORT) as client:
                data = (await client.post("https://sms.ru/sms/send", data=params)).json()
        except (httpx.HTTPError, ValueError) as exc:
            raise CodeError("Не удалось отправить SMS, попробуйте позже", 503) from exc
        sms = (data.get("sms") or {}).get(phone.lstrip("+")) or {}
        if data.get("status") != "OK" or sms.get("status") != "OK":
            log.warning("sms.ru error: %s", data)
            raise CodeError("Не удалось отправить SMS, попробуйте позже", 503)
        return
    if s.sms_provider == "console" and not s.is_prod:
        log.warning("SMS на %s: %s", phone, text)  # разработка: код виден в логе сервера
        return
    raise CodeError("Вход по SMS пока не настроен", 503)


def email_configured() -> bool:
    s = get_settings()
    return bool(s.smtp_host and s.smtp_user and s.smtp_password)


async def send_email(to: str, subject: str, body: str) -> None:
    s = get_settings()
    msg = EmailMessage()
    msg["From"] = s.smtp_from or s.smtp_user or "noreply@localhost"
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)
    if SENT_EMAILS is not None:
        SENT_EMAILS.append(msg)
        return
    if not email_configured():
        if not s.is_prod:
            log.warning("Письмо для %s: %s", to, body.splitlines()[0])  # разработка: код в логе
            return
        raise CodeError("Вход по коду на email пока не настроен — войдите по паролю", 503)
    try:
        await asyncio.to_thread(_smtp_send, msg)
    except (smtplib.SMTPException, OSError) as exc:
        log.warning("SMTP error: %s", exc)
        raise CodeError("Не удалось отправить письмо, попробуйте позже", 503) from exc


def _smtp_send(msg: EmailMessage) -> None:
    s = get_settings()
    ctx = ssl.create_default_context()
    if s.smtp_security == "ssl":
        with smtplib.SMTP_SSL(s.smtp_host, s.smtp_port, context=ctx, timeout=15) as smtp:
            smtp.login(s.smtp_user, s.smtp_password.get_secret_value())
            smtp.send_message(msg)
    else:
        with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=15) as smtp:
            smtp.starttls(context=ctx)
            smtp.login(s.smtp_user, s.smtp_password.get_secret_value())
            smtp.send_message(msg)
