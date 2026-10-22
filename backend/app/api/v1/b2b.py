from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.api.deps import CurrentUser, SessionDep, require
from app.core.rate_limit import limiter
from app.models import (
    AccountType,
    B2BAccount,
    B2BStatus,
    Permission,
)
from app.schemas.catalog import MoneyOut
from app.services.geo import get_settings_row

router = APIRouter(tags=["b2b"])

_INN10 = (2, 4, 10, 3, 5, 9, 4, 6, 8)
_INN11 = (7, 2, 4, 10, 3, 5, 9, 4, 6, 8)
_INN12 = (3, 7, 2, 4, 10, 3, 5, 9, 4, 6, 8)


def _check_digit(digits: list[int], weights: tuple[int, ...]) -> int:
    return sum(d * w for d, w in zip(digits, weights, strict=False)) % 11 % 10


def inn_is_valid(inn: str) -> bool:
    if not inn.isdigit() or len(inn) not in (10, 12):
        return False
    d = [int(c) for c in inn]
    if len(d) == 10:
        return _check_digit(d, _INN10) == d[9]
    return _check_digit(d, _INN11) == d[10] and _check_digit(d, _INN12) == d[11]


class ApplicationIn(BaseModel):
    legal_name: str = Field(min_length=2, max_length=255)
    tax_id: str

    @field_validator("legal_name")
    @classmethod
    def _name(cls, v: str) -> str:
        v = " ".join(v.split())
        if len(v) < 2:
            raise ValueError("Укажите название компании")
        return v

    @field_validator("tax_id")
    @classmethod
    def _inn(cls, v: str) -> str:
        v = "".join(v.split())
        if not inn_is_valid(v):
            raise ValueError("Проверьте ИНН: 10 цифр у компании, 12 — у ИП")
        return v


class ApplicationOut(BaseModel):
    status: str
    legal_name: str
    tax_id: str


@router.post("/me/b2b-application", response_model=ApplicationOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/hour")
async def apply_b2b(request: Request, body: ApplicationIn, user: CurrentUser, session: SessionDep) -> ApplicationOut:
    if user.role.is_staff:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Заявку подаёт покупатель, а не сотрудник магазина")
    acc = user.b2b_account
    if acc is not None and acc.status in (B2BStatus.PENDING, B2BStatus.APPROVED, B2BStatus.SUSPENDED):
        raise HTTPException(status.HTTP_409_CONFLICT, "Заявка уже отправлена")
    taken = await session.scalar(select(B2BAccount.id).where(B2BAccount.tax_id == body.tax_id))
    if taken is not None and (acc is None or taken != acc.id):
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Компания с таким ИНН уже подключена — свяжитесь с нами, и мы добавим вас к ней"
        )
    if acc is None:
        acc = B2BAccount(legal_name=body.legal_name, tax_id=body.tax_id)
        session.add(acc)
        user.account_type = AccountType.B2B
        user.b2b_account = acc
    else:
        # повторная заявка после отказа — та же запись компании, снова на проверку
        acc.legal_name, acc.tax_id = body.legal_name, body.tax_id
        acc.verified_at = acc.verified_by_id = acc.manager_note = None
    acc.status = B2BStatus.PENDING
    await session.flush()
    return ApplicationOut(status=acc.status.value, legal_name=acc.legal_name, tax_id=acc.tax_id)


class MemberOut(BaseModel):
    id: int
    full_name: str
    phone: str | None
    email: str | None


class CompanyOut(BaseModel):
    id: int
    legal_name: str
    tax_id: str
    status: str
    note: str | None
    created_at: datetime
    verified_at: datetime | None
    members: list[MemberOut]


@router.get(
    "/admin/b2b-accounts",
    response_model=list[CompanyOut],
    dependencies=[Depends(require(Permission.B2B_MANAGE))],
)
async def list_companies(session: SessionDep) -> list[CompanyOut]:
    rows = (
        await session.scalars(
            select(B2BAccount).options(selectinload(B2BAccount.members)).order_by(B2BAccount.created_at.desc())
        )
    ).unique()
    return [
        CompanyOut(
            id=a.id,
            legal_name=a.legal_name,
            tax_id=a.tax_id,
            status=a.status.value,
            note=a.manager_note,
            created_at=a.created_at,
            verified_at=a.verified_at,
            members=[
                MemberOut(id=m.id, full_name=m.full_name, phone=m.phone_e164 or m.phone, email=m.email)
                for m in a.members
            ],
        )
        for a in rows
    ]


class WholesaleSettingsIO(BaseModel):
    min_order: Decimal = Field(ge=0, le=10_000_000, max_digits=12, decimal_places=2)


class WholesaleSettingsOut(BaseModel):
    min_order: MoneyOut


@router.get(
    "/admin/settings/wholesale",
    response_model=WholesaleSettingsOut,
    dependencies=[Depends(require(Permission.B2B_MANAGE))],
)
async def get_wholesale_settings(session: SessionDep) -> WholesaleSettingsOut:
    return WholesaleSettingsOut(min_order=(await get_settings_row(session)).wholesale_min_order)


@router.put(
    "/admin/settings/wholesale",
    response_model=WholesaleSettingsOut,
    dependencies=[Depends(require(Permission.B2B_MANAGE))],
)
async def set_wholesale_settings(body: WholesaleSettingsIO, session: SessionDep) -> WholesaleSettingsOut:
    (await get_settings_row(session)).wholesale_min_order = body.min_order
    return WholesaleSettingsOut(min_order=body.min_order)
