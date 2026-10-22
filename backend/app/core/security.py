import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from app.core.config import get_settings

TokenType = Literal["access", "refresh"]

_hasher = PasswordHasher()  # Argon2id, параметры по умолчанию RFC 9106


# Самые частые пароли из утечек: проходят «буквы+цифры», но подбираются за секунды
_COMMON = {
    "password1",
    "password123",
    "qwerty123",
    "qwerty12",
    "qwertyuiop1",
    "1q2w3e4r",
    "1q2w3e4r5t",
    "1qaz2wsx",
    "zaq12wsx",
    "abc12345",
    "abcd1234",
    "admin123",
    "admin1234",
    "iloveyou1",
    "welcome1",
    "passw0rd",
    "p@ssw0rd",
    "letmein1",
    "11111111a",
    "a1234567",
    "a12345678",
    "q1w2e3r4",
    "q1w2e3r4t5",
    "parol123",
    "privet123",
    "qwe12345",
    "asdf1234",
    "test1234",
    "user1234",
    "1234qwer",
    "12345qwe",
    "123456789a",
    "123qweasd",
    "qweasd123",
    "qazwsx123",
    "pass1234",
    "monkey123",
    "dragon123",
    "football1",
    "baseball1",
}


def password_problem(password: str, email: str | None = None) -> str | None:
    """Почему пароль не годится (None — годится). Одни правила для покупателей и сотрудников."""
    if len(password) < 8:
        return "Пароль должен быть не короче 8 символов"
    if len(password) > 128:
        return "Пароль слишком длинный"
    if not any(c.isalpha() for c in password) or not any(c.isdigit() for c in password):
        return "Пароль должен содержать и буквы, и цифры"
    if password.lower() in _COMMON or len(set(password)) < 4:
        return "Этот пароль слишком простой — его легко подобрать"
    local = (email or "").split("@")[0].lower()
    if len(local) >= 4 and local in password.lower():
        return "Пароль не должен содержать ваш email"
    return None


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except (VerifyMismatchError, InvalidHashError):
        return False


def needs_rehash(password_hash: str) -> bool:
    return _hasher.check_needs_rehash(password_hash)


def create_token(subject: int, token_type: TokenType, extra: dict[str, Any] | None = None) -> tuple[str, str, datetime]:
    """Возвращает (token, jti, expires_at). jti нужен для отзыва refresh-токенов."""
    s = get_settings()
    now = datetime.now(UTC)
    ttl = (
        timedelta(minutes=s.access_token_ttl_min)
        if token_type == "access"
        else timedelta(days=s.refresh_token_ttl_days)
    )
    jti = uuid.uuid4().hex
    payload = {
        "sub": str(subject),
        "type": token_type,
        "jti": jti,
        "iat": now.timestamp(),  # дробные секунды: точное сравнение с users.tokens_valid_after
        "exp": now + ttl,
        **(extra or {}),
    }
    token = jwt.encode(payload, s.jwt_secret.get_secret_value(), algorithm=s.jwt_algorithm)
    return token, jti, now + ttl


def decode_token(token: str, expected_type: TokenType) -> dict[str, Any]:
    s = get_settings()
    payload = jwt.decode(
        token,
        s.jwt_secret.get_secret_value(),
        algorithms=[s.jwt_algorithm],  # фиксируем алгоритм — защита от alg=none / подмены
        options={"require": ["exp", "sub", "type", "jti"]},
    )
    if payload["type"] != expected_type:
        raise jwt.InvalidTokenError("Wrong token type")
    return payload
