from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import decode_token
from app.db.session import get_session
from app.models import Permission, User
from app.models.user import role_permissions
from app.repositories.loyalty import LoyaltyTierRepository, UserRepository
from app.repositories.product import ProductRepository
from app.services.cart import CartService
from app.services.import_export import ProductImportService
from app.services.loyalty import LoyaltyService
from app.services.orders import OrderService
from app.services.pricing import PricingRepository, PricingService
from app.services.recommendations import RecommendationService

SessionDep = Annotated[AsyncSession, Depends(get_session)]
oauth2 = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")
oauth2_optional = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login", auto_error=False)

_CREDENTIALS_ERROR = HTTPException(
    status.HTTP_401_UNAUTHORIZED, "Could not validate credentials", headers={"WWW-Authenticate": "Bearer"}
)


async def get_current_user(session: SessionDep, token: Annotated[str, Depends(oauth2)]) -> User:
    try:
        payload = decode_token(token, "access")
    except jwt.PyJWTError:
        raise _CREDENTIALS_ERROR from None
    user = await session.get(User, int(payload["sub"]))
    if user is None or not user.is_active:
        raise _CREDENTIALS_ERROR
    if user.tokens_valid_after and payload.get("iat", 0) < user.tokens_valid_after.timestamp():
        raise _CREDENTIALS_ERROR  # токен выпущен до смены пароля / «выйти на всех устройствах»
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


async def get_optional_user(session: SessionDep, token: Annotated[str | None, Depends(oauth2_optional)]) -> User | None:
    """
    Для публичных эндпоинтов с персональными ценами.
    Нет токена → аноним. Есть, но невалидный/просроченный → 401, а НЕ тихий аноним:
    иначе оптовик с протухшим access-токеном молча увидит розничные цены вместо refresh.
    """
    if token is None:
        return None
    return await get_current_user(session, token)


OptionalUser = Annotated[User | None, Depends(get_optional_user)]


async def get_permissions(session: SessionDep, user: CurrentUser) -> frozenset[Permission]:
    # Права читаются из БД на каждый запрос: отзыв роли действует мгновенно, а не по истечении токена.
    # При нагрузке — кэш в Redis с инвалидацией при изменении роли.
    rows = await session.scalars(
        select(role_permissions.c.permission).where(role_permissions.c.role_id == user.role_id)
    )
    return frozenset(rows)


PermissionsDep = Annotated[frozenset[Permission], Depends(get_permissions)]


def require(*needed: Permission):

    async def guard(user: CurrentUser, perms: PermissionsDep) -> User:
        if not set(needed) <= perms:
            # 403, а не 404: пользователь аутентифицирован, но прав нет
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Insufficient permissions")
        return user

    return guard


def get_loyalty_service(session: SessionDep) -> LoyaltyService:
    return LoyaltyService(UserRepository(session), LoyaltyTierRepository(session))


def get_import_service(session: SessionDep) -> ProductImportService:
    return ProductImportService(ProductRepository(session))


def get_pricing_service(session: SessionDep) -> PricingService:
    return PricingService(PricingRepository(session))


def get_cart_service(pricing: Annotated[PricingService, Depends(get_pricing_service)]) -> CartService:
    return CartService(pricing)


def get_order_service(
    session: SessionDep,
    cart: Annotated[CartService, Depends(get_cart_service)],
    loyalty: Annotated[LoyaltyService, Depends(get_loyalty_service)],
) -> OrderService:
    return OrderService(session, cart, loyalty)


def get_recommendation_service(session: SessionDep) -> RecommendationService:
    return RecommendationService(session)
