from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select

from app.api.deps import SessionDep, require
from app.models import B2BAccount, B2BStatus, Permission, PriceList, RelationKind, User
from app.repositories.catalog import CatalogRepository
from app.schemas.catalog import ProductRelationsIn

router = APIRouter(prefix="/admin", tags=["admin: merchandising & b2b"])


@router.put("/products/{product_id}/relations", status_code=status.HTTP_204_NO_CONTENT)
async def set_product_relations(
    product_id: int,
    body: ProductRelationsIn,
    session: SessionDep,
    _: Annotated[User, Depends(require(Permission.PRODUCTS_WRITE))],
) -> None:
    repo = CatalogRepository(session)
    product = await repo.get(product_id)
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Product not found")

    all_ids = [*body.cross_sell, *body.upsell]
    if product_id in all_ids:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Product cannot reference itself")
    if missing := set(all_ids) - await repo.existing_ids(all_ids):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, f"Unknown product ids: {sorted(missing)}")

    await repo.replace_relations(product_id, RelationKind.CROSS_SELL, body.cross_sell)
    await repo.replace_relations(product_id, RelationKind.UPSELL, body.upsell)


class B2BDecisionIn(BaseModel):
    approve: bool
    price_list_id: int | None = None
    note: str | None = None


@router.post("/b2b-accounts/{account_id}/decision", status_code=status.HTTP_204_NO_CONTENT)
async def decide_b2b_account(
    account_id: int,
    body: B2BDecisionIn,
    session: SessionDep,
    admin: Annotated[User, Depends(require(Permission.B2B_MANAGE))],
) -> None:
    # of=B2BAccount: у компании eager-JOIN на прайс-лист — блокируем только саму строку компании
    account = await session.scalar(select(B2BAccount).where(B2BAccount.id == account_id).with_for_update(of=B2BAccount))
    if account is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "B2B account not found")
    if body.approve and body.price_list_id is not None:
        if await session.get(PriceList, body.price_list_id) is None:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Price list not found")
        account.price_list_id = body.price_list_id
    account.status = B2BStatus.APPROVED if body.approve else B2BStatus.REJECTED
    account.verified_at = datetime.now(UTC)
    account.verified_by_id = admin.id
    account.manager_note = body.note
