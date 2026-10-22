import secrets
from datetime import UTC, datetime, timedelta
from typing import Annotated

import jwt
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel, EmailStr, Field, model_validator
from sqlalchemy import select, update

from app.api.deps import CurrentUser, PermissionsDep, SessionDep
from app.core import login_guard
from app.core.config import get_settings
from app.core.rate_limit import AUTH_LIMIT, limiter
from app.core.security import (
    create_token,
    decode_token,
    hash_password,
    needs_rehash,
    password_problem,
    verify_password,
)
from app.models import RefreshToken, SystemRole, User
from app.repositories.loyalty import UserRepository
from app.services.bootstrap import ensure_system_roles
from app.services.login_codes import Channel, CodeError, check_code, email_configured, issue_code, normalize_phone

router = APIRouter(prefix="/auth", tags=["auth"])

# Хэш-«пустышка»: при несуществующем email тратим столько же времени → нет timing-атаки на перебор email
_DUMMY_HASH = hash_password("dummy-password-for-timing")


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshIn(BaseModel):
    refresh_token: str | None = None  # сайт (X-Session: cookie) не передаёт — токен в HttpOnly-cookie


REFRESH_COOKIE = "rt"
REUSE_GRACE = timedelta(seconds=30)


def _refresh_from(request: Request, body: RefreshIn | None) -> str | None:
    return (body.refresh_token if body else None) or request.cookies.get(REFRESH_COOKIE)


async def _issue_pair(session: SessionDep, user: User, request: Request) -> TokenPair:
    access, _, _ = create_token(user.id, "access", {"role": user.role.code})
    refresh, jti, expires = create_token(user.id, "refresh")
    session.add(
        RefreshToken(
            user_id=user.id, jti=jti, expires_at=expires, user_agent=request.headers.get("user-agent", "")[:255]
        )
    )
    request.state.issued_refresh = refresh  # для сайта middleware переложит его в HttpOnly-cookie
    return TokenPair(access_token=access, refresh_token=refresh)


@router.post("/login", response_model=TokenPair)
@limiter.limit(AUTH_LIMIT)
async def login(
    request: Request, session: SessionDep, form: Annotated[OAuth2PasswordRequestForm, Depends()]
) -> TokenPair:
    if wait := await login_guard.locked_for(form.username):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            f"Слишком много неудачных попыток. Вход временно закрыт — попробуйте через {wait // 60 + 1} мин.",
            headers={"Retry-After": str(wait)},
        )
    user = await UserRepository(session).get_by_email(form.username)
    password_ok = verify_password(form.password, user.password_hash if user else _DUMMY_HASH)
    if not user or not password_ok or not user.is_active:
        await login_guard.register_failure(form.username)
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, "Invalid email or password"
        )  # не раскрываем, что именно не так
    await login_guard.register_success(form.username)
    if needs_rehash(user.password_hash):
        user.password_hash = hash_password(form.password)
    return await _issue_pair(session, user, request)


@router.post("/refresh", response_model=TokenPair)
@limiter.limit("20/minute")
async def refresh(request: Request, session: SessionDep, body: RefreshIn | None = None) -> TokenPair:
    """Ротация: старый refresh отзывается. Повторное использование отозванного → отзыв ВСЕХ токенов (кража)."""
    token = _refresh_from(request, body)
    if not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid refresh token")
    try:
        payload = decode_token(token, "refresh")
    except jwt.PyJWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid refresh token") from None

    stored = await session.scalar(select(RefreshToken).where(RefreshToken.jti == payload["jti"]).with_for_update())
    now = datetime.now(UTC)
    if stored is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid refresh token")
    in_grace = stored.rotated_at is not None and now - stored.rotated_at <= REUSE_GRACE
    if stored.revoked_at is not None and in_grace:
        # Ответ на прошлую ротацию не дошёл до клиента — продолжаем сессию, а не считаем это кражей
        user = await session.get(User, stored.user_id)
        if user is None or not user.is_active:
            raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User inactive")
        return await _issue_pair(session, user, request)
    if stored.revoked_at is not None:
        await session.execute(
            update(RefreshToken)
            .where(RefreshToken.user_id == stored.user_id, RefreshToken.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        await session.commit()  # фиксируем отзыв до выброса ошибки
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Refresh token reuse detected")

    stored.revoked_at = stored.rotated_at = now
    user = await session.get(User, stored.user_id)
    if user is None or not user.is_active:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User inactive")
    return await _issue_pair(session, user, request)


class RegisterIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    full_name: str = Field(min_length=2, max_length=200)
    phone: str | None = Field(default=None, pattern=r"^\+?[0-9 ()\-]{7,20}$")

    @model_validator(mode="after")
    def _strength(self):
        if problem := password_problem(self.password, self.email):
            raise ValueError(problem)
        return self


@router.post("/register", response_model=TokenPair, status_code=status.HTTP_201_CREATED)
@limiter.limit(AUTH_LIMIT)
async def register(request: Request, session: SessionDep, body: RegisterIn) -> TokenPair:
    """Регистрация покупателя. Сотрудников создаёт владелец в админке, не через этот эндпоинт."""
    if await UserRepository(session).get_by_email(body.email) is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Email is already registered")
    roles = await ensure_system_roles(session)
    user = User(
        email=body.email.lower(),
        password_hash=hash_password(body.password),
        full_name=body.full_name.strip(),
        phone=body.phone,
        role_id=roles[SystemRole.CUSTOMER].id,
    )
    session.add(user)
    await session.flush()
    await session.refresh(user, ["role"])
    return await _issue_pair(session, user, request)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(request: Request, session: SessionDep, body: RefreshIn | None = None) -> None:
    """Отзывает refresh-токен этого устройства. Невалидный токен — тоже 204 (logout идемпотентен)."""
    request.state.clear_refresh_cookie = True
    try:
        payload = decode_token(_refresh_from(request, body) or "", "refresh")
    except jwt.PyJWTError:
        return
    await session.execute(
        update(RefreshToken)
        .where(RefreshToken.jti == payload["jti"], RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )


async def _revoke_everything(session, user: User) -> None:
    """Отзывает все refresh-токены и делает недействительными уже выданные access-токены."""
    now = datetime.now(UTC)
    user.tokens_valid_after = now
    await session.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=now)
    )


class ChangePasswordIn(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


@router.post("/change-password", response_model=TokenPair)
@limiter.limit(AUTH_LIMIT)
async def change_password(
    request: Request, body: ChangePasswordIn, user: CurrentUser, session: SessionDep
) -> TokenPair:
    """Смена пароля: остальные устройства разлогиниваются, этому выдаём новую пару токенов."""
    if not verify_password(body.current_password, user.password_hash):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Текущий пароль указан неверно")
    if problem := password_problem(body.new_password, user.email):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, problem)
    if verify_password(body.new_password, user.password_hash):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Новый пароль совпадает со старым")
    user.password_hash = hash_password(body.new_password)
    await _revoke_everything(session, user)
    return await _issue_pair(session, user, request)


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
async def logout_all(request: Request, user: CurrentUser, session: SessionDep) -> None:
    request.state.clear_refresh_cookie = True
    await _revoke_everything(session, user)


# Шаг 1 request → код уходит в SMS/на почту; шаг 2 verify → вход (или токен регистрации для нового);
# шаг 3 complete → имя, аккаунт создан. Ответы одинаковы для новых и существующих — не раскрываем базу.

_SIGNUP_TTL = timedelta(minutes=15)


class CodeSentOut(BaseModel):
    target: str  # нормализованный номер (+79161234567) или email в нижнем регистре
    resend_in: int
    dev_code: str | None = None  # только в разработке, чтобы войти без настоящей SMS/письма
    # совместимость со старым клиентом
    phone: str | None = None


class VerifyOut(BaseModel):
    status: str  # ok — вошли; need_name — новый аккаунт, нужно имя (шаг 3)
    access_token: str | None = None
    refresh_token: str | None = None
    signup_token: str | None = None


def _dev_code(code: str, channel: str) -> str | None:
    s = get_settings()
    if s.app_env not in ("dev", "test"):
        return None
    if channel == "sms":
        return code if s.sms_provider == "console" else None
    return None if email_configured() else code


async def _request(request: Request, session, channel: Channel, target: str) -> CodeSentOut:
    try:
        code, resend_in = await issue_code(session, channel, target, request.client.host if request.client else None)
    except CodeError as exc:
        headers = {"Retry-After": str(exc.retry_after)} if exc.retry_after else None
        raise HTTPException(exc.status, str(exc), headers=headers) from exc
    return CodeSentOut(
        target=target,
        resend_in=resend_in,
        dev_code=_dev_code(code, channel),
        phone=target if channel == "sms" else None,
    )


async def _verify(request: Request, session, channel: Channel, target: str, code: str) -> VerifyOut:
    try:
        await check_code(session, channel, target, code)
    except CodeError as exc:
        await session.commit()  # счётчик попыток должен сохраниться, даже когда отвечаем ошибкой
        raise HTTPException(exc.status, str(exc)) from exc
    if channel == "sms":
        user = await session.scalar(select(User).where(User.phone_e164 == target))
    else:
        user = await UserRepository(session).get_by_email(target)
    if user is not None:
        if not user.is_active:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Аккаунт заблокирован")
        if channel == "email" and user.email_verified_at is None:
            user.email_verified_at = datetime.now(UTC)  # код из письма = почта подтверждена
        pair = await _issue_pair(session, user, request)
        return VerifyOut(status="ok", access_token=pair.access_token, refresh_token=pair.refresh_token)
    s = get_settings()
    token = jwt.encode(
        {"type": "signup", "channel": channel, "target": target, "exp": datetime.now(UTC) + _SIGNUP_TTL},
        s.jwt_secret.get_secret_value(),
        algorithm=s.jwt_algorithm,
    )
    return VerifyOut(status="need_name", signup_token=token)


class CompleteIn(BaseModel):
    signup_token: str
    full_name: str = Field(min_length=2, max_length=200)


async def _complete(request: Request, session, body: CompleteIn) -> TokenPair:
    s = get_settings()
    try:
        payload = jwt.decode(
            body.signup_token,
            s.jwt_secret.get_secret_value(),
            algorithms=[s.jwt_algorithm],
            options={"require": ["exp", "type", "channel", "target"]},
        )
    except jwt.PyJWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Подтверждение устарело — запросите код ещё раз") from None
    if payload["type"] != "signup":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверный токен")
    channel, target, now = payload["channel"], payload["target"], datetime.now(UTC)
    if channel == "sms":
        user = await session.scalar(select(User).where(User.phone_e164 == target))
    else:
        user = await UserRepository(session).get_by_email(target)
    if user is None:  # повторный запрос с тем же токеном просто войдёт в уже созданный аккаунт
        roles = await ensure_system_roles(session)
        user = User(
            full_name=body.full_name.strip(),
            role_id=roles[SystemRole.CUSTOMER].id,
            password_hash=hash_password(secrets.token_urlsafe(32)),  # пароля нет: вход по коду
            **(
                {"phone_e164": target, "phone": target, "phone_verified_at": now}
                if channel == "sms"
                else {"email": target, "email_verified_at": now}
            ),
        )
        session.add(user)
        await session.flush()
        await session.refresh(user, ["role"])
    return await _issue_pair(session, user, request)


class PhoneIn(BaseModel):
    phone: str = Field(min_length=10, max_length=20)


class PhoneVerifyIn(PhoneIn):
    code: str = Field(min_length=4, max_length=8)


def _phone(raw: str) -> str:
    phone = normalize_phone(raw)
    if phone is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Укажите мобильный номер России: +7 9XX XXX-XX-XX")
    return phone


@router.post("/phone/request", response_model=CodeSentOut)
@limiter.limit("5/minute")
async def phone_request(request: Request, body: PhoneIn, session: SessionDep) -> CodeSentOut:
    return await _request(request, session, "sms", _phone(body.phone))


@router.post("/phone/verify", response_model=VerifyOut)
@limiter.limit("10/minute")
async def phone_verify(request: Request, body: PhoneVerifyIn, session: SessionDep) -> VerifyOut:
    return await _verify(request, session, "sms", _phone(body.phone), body.code)


@router.post("/phone/complete", response_model=TokenPair, status_code=status.HTTP_201_CREATED)
@limiter.limit(AUTH_LIMIT)
async def phone_complete(request: Request, body: CompleteIn, session: SessionDep) -> TokenPair:
    return await _complete(request, session, body)


class EmailIn(BaseModel):
    email: EmailStr


class EmailVerifyIn(EmailIn):
    code: str = Field(min_length=4, max_length=8)


@router.post("/email/request", response_model=CodeSentOut)
@limiter.limit("5/minute")
async def email_request(request: Request, body: EmailIn, session: SessionDep) -> CodeSentOut:
    """Код на почту: вход без пароля, а для новых — регистрация с подтверждённым email."""
    return await _request(request, session, "email", body.email.lower())


@router.post("/email/verify", response_model=VerifyOut)
@limiter.limit("10/minute")
async def email_verify(request: Request, body: EmailVerifyIn, session: SessionDep) -> VerifyOut:
    return await _verify(request, session, "email", body.email.lower(), body.code)


@router.post("/email/complete", response_model=TokenPair, status_code=status.HTTP_201_CREATED)
@limiter.limit(AUTH_LIMIT)
async def email_complete(request: Request, body: CompleteIn, session: SessionDep) -> TokenPair:
    return await _complete(request, session, body)


class B2BOut(BaseModel):
    status: str
    legal_name: str


class MeOut(BaseModel):
    id: int
    email: str | None
    full_name: str
    phone: str | None
    avatar_url: str | None
    account_type: str
    b2b: B2BOut | None
    is_staff: bool
    role: str
    role_title: str
    permissions: list[str]


@router.get("/me", response_model=MeOut)
async def me(user: CurrentUser, perms: PermissionsDep) -> MeOut:
    acc = user.b2b_account
    return MeOut(
        id=user.id,
        email=user.email,
        full_name=user.full_name,
        phone=user.phone,
        avatar_url=user.avatar_url,
        account_type=user.account_type.value,
        b2b=B2BOut(status=acc.status.value, legal_name=acc.legal_name) if acc else None,
        is_staff=user.role.is_staff,
        role=user.role.code,
        role_title=user.role.title,
        permissions=sorted(p.value for p in perms),
    )
