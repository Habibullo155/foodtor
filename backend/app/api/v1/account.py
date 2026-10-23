import io
import secrets
from datetime import datetime
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel, Field
from sqlalchemy import func, select, update

from app.api.deps import CurrentUser, SessionDep, require
from app.core.config import get_settings
from app.models import (
    Order,
    OrderComment,
    OrderItem,
    OrderStatus,
    Permission,
    Product,
    User,
    UserAddress,
)
from app.models.address import MAX_ADDRESSES
from app.schemas.catalog import MoneyOut
from app.services.geo import DeliveryCheck, Point, check_delivery

router = APIRouter(tags=["account"])

AVATAR_MAX_BYTES = 5 * 2**20
AVATAR_SIZE = 256
Image.MAX_IMAGE_PIXELS = 25_000_000  # защита от «декомпрессионных бомб»


class ProfileIn(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=200)
    phone: str | None = Field(default=None, pattern=r"^\+?[0-9 ()\-]{7,20}$")


class ProfileOut(BaseModel):
    full_name: str
    phone: str | None
    avatar_url: str | None


@router.patch("/me/profile", response_model=ProfileOut)
async def update_profile(body: ProfileIn, user: CurrentUser, session: SessionDep) -> ProfileOut:
    if body.full_name is not None:
        user.full_name = body.full_name.strip()
    if body.phone is not None:
        user.phone = body.phone.strip()
    return ProfileOut(full_name=user.full_name, phone=user.phone, avatar_url=user.avatar_url)


def _avatar_dir() -> Path:
    d = Path(get_settings().media_root) / "avatars"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _remove_old_avatar(url: str | None) -> None:
    if url and url.startswith(get_settings().media_url + "/avatars/"):
        (_avatar_dir() / Path(url).name).unlink(missing_ok=True)


Image.MAX_IMAGE_PIXELS = 40_000_000  # «бомба» из миллиардов пикселей отклоняется до декодирования


def _process_avatar(raw: bytes) -> bytes:
    """Проверка, что это действительно картинка; квадрат по центру; 256×256 WebP без EXIF (геометки и т.п.)."""
    try:
        img = Image.open(io.BytesIO(raw))
        img.verify()  # проверяет структуру файла, не декодируя целиком
        img = Image.open(io.BytesIO(raw))
        img = ImageOps.exif_transpose(img).convert("RGB")
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError) as exc:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "File is not a valid image") from exc
    img = ImageOps.fit(img, (AVATAR_SIZE, AVATAR_SIZE), Image.Resampling.LANCZOS)
    out = io.BytesIO()
    img.save(out, "WEBP", quality=85)  # пересохранение отбрасывает метаданные и полезную нагрузку из исходника
    return out.getvalue()


@router.post("/me/avatar", response_model=ProfileOut)
async def upload_avatar(user: CurrentUser, file: Annotated[UploadFile, File()]) -> ProfileOut:
    raw = await file.read(AVATAR_MAX_BYTES + 1)
    if len(raw) > AVATAR_MAX_BYTES:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "Image must be under 5 MB")
    data = _process_avatar(raw)
    name = f"{user.id}-{secrets.token_hex(8)}.webp"  # случайное имя: нельзя угадать/перезаписать чужой файл
    (_avatar_dir() / name).write_bytes(data)
    _remove_old_avatar(user.avatar_url)
    user.avatar_url = f"{get_settings().media_url}/avatars/{name}"
    return ProfileOut(full_name=user.full_name, phone=user.phone, avatar_url=user.avatar_url)


@router.delete("/me/avatar", response_model=ProfileOut)
async def delete_avatar(user: CurrentUser) -> ProfileOut:
    _remove_old_avatar(user.avatar_url)
    user.avatar_url = None
    return ProfileOut(full_name=user.full_name, phone=user.phone, avatar_url=None)


class AddressIn(BaseModel):
    label: str = Field(default="Дом", min_length=1, max_length=40)
    address: str = Field(min_length=5, max_length=300)
    apartment: str | None = Field(default=None, max_length=20)
    entrance: str | None = Field(default=None, max_length=10)
    floor: str | None = Field(default=None, max_length=10)
    intercom: str | None = Field(default=None, max_length=20)
    courier_note: str | None = Field(default=None, max_length=300)
    is_default: bool = False
    lat: float | None = Field(default=None, ge=-90, le=90)  # точка с карты (если выбирали)
    lng: float | None = Field(default=None, ge=-180, le=180)


class AddressOut(AddressIn):
    id: int
    one_line: str
    in_zone: bool | None = None  # None — не удалось проверить (геокодер недоступен)
    zone_message: str | None = None


def _addr_out(a: UserAddress, zone: DeliveryCheck | None = None) -> AddressOut:
    return AddressOut(
        in_zone=zone.ok if zone and (zone.point or not zone.ok) else None,
        zone_message=zone.reason if zone else None,
        id=a.id,
        label=a.label,
        address=a.address,
        apartment=a.apartment,
        entrance=a.entrance,
        floor=a.floor,
        intercom=a.intercom,
        courier_note=a.courier_note,
        is_default=a.is_default,
        one_line=a.one_line(),
        lat=a.lat,
        lng=a.lng,
    )


async def _my_address(session, user: User, address_id: int) -> UserAddress:
    a = await session.get(UserAddress, address_id)
    if a is None or a.user_id != user.id:  # чужой адрес — как будто его нет (не раскрываем существование)
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Address not found")
    return a


async def _locate(session, a: UserAddress) -> DeliveryCheck:
    """Геокодинг адреса + проверка зоны. Адрес вне зоны сохраняем (вдруг радиус расширят), но предупреждаем."""
    picked = Point(a.lat, a.lng) if a.lat is not None and a.lng is not None else None
    zone = await check_delivery(session, a.address, picked)
    a.lat, a.lng = (zone.point.lat, zone.point.lng) if zone.point else (None, None)
    return zone


async def _make_default(session, user: User, a: UserAddress) -> None:
    await session.execute(update(UserAddress).where(UserAddress.user_id == user.id).values(is_default=False))
    a.is_default = True


@router.get("/me/addresses", response_model=list[AddressOut])
async def my_addresses(user: CurrentUser, session: SessionDep):
    rows = await session.scalars(
        select(UserAddress)
        .where(UserAddress.user_id == user.id)
        .order_by(UserAddress.is_default.desc(), UserAddress.id)
    )
    return [_addr_out(a) for a in rows]


@router.post("/me/addresses", response_model=AddressOut, status_code=201)
async def add_address(body: AddressIn, user: CurrentUser, session: SessionDep):
    count = await session.scalar(select(func.count()).select_from(UserAddress).where(UserAddress.user_id == user.id))
    if count >= MAX_ADDRESSES:
        raise HTTPException(status.HTTP_409_CONFLICT, f"Maximum {MAX_ADDRESSES} addresses")
    a = UserAddress(user_id=user.id, **body.model_dump(exclude={"is_default"}))
    zone = await _locate(session, a)
    session.add(a)
    await session.flush()
    if body.is_default or count == 0:  # первый адрес — сразу по умолчанию
        await _make_default(session, user, a)
    return _addr_out(a, zone)


@router.put("/me/addresses/{address_id}", response_model=AddressOut)
async def edit_address(address_id: int, body: AddressIn, user: CurrentUser, session: SessionDep):
    a = await _my_address(session, user, address_id)
    for k, v in body.model_dump(exclude={"is_default"}).items():
        setattr(a, k, v)
    zone = await _locate(session, a)
    if body.is_default:
        await _make_default(session, user, a)
    return _addr_out(a, zone)


@router.delete("/me/addresses/{address_id}", status_code=204)
async def delete_address(address_id: int, user: CurrentUser, session: SessionDep):
    a = await _my_address(session, user, address_id)
    was_default = a.is_default
    await session.delete(a)
    await session.flush()
    if was_default:  # следующий по порядку становится основным
        nxt = await session.scalar(select(UserAddress).where(UserAddress.user_id == user.id).order_by(UserAddress.id))
        if nxt:
            nxt.is_default = True


class PurchaseOut(BaseModel):
    product_id: int
    name: str
    image_url: str | None
    unit: str | None
    times_bought: int
    total_quantity: int
    last_bought_at: datetime
    price: MoneyOut | None  # текущая розничная цена; None — товар снят с продажи
    in_stock: bool


@router.get("/me/purchases", response_model=list[PurchaseOut])
async def my_purchases(user: CurrentUser, session: SessionDep):
    """Что покупатель уже покупал (доставленные заказы) — для «Купить снова». Свежие покупки первыми."""
    rows = await session.execute(
        select(
            OrderItem.product_id,
            func.count(func.distinct(Order.id)),
            func.sum(OrderItem.quantity),
            func.max(Order.created_at),
        )
        .join(Order, Order.id == OrderItem.order_id)
        .where(Order.user_id == user.id, Order.status == OrderStatus.DELIVERED, OrderItem.product_id.is_not(None))
        .group_by(OrderItem.product_id)
        .order_by(func.max(Order.created_at).desc())
        .limit(200)
    )
    stats = {pid: (n, qty, last) for pid, n, qty, last in rows}
    products = {p.id: p for p in (await session.scalars(select(Product).where(Product.id.in_(stats)))).unique()}
    out = []
    for pid, (n, qty, last) in stats.items():
        p = products.get(pid)
        if p is None:
            continue
        out.append(
            PurchaseOut(
                product_id=pid,
                name=p.name,
                image_url=p.images[0].url if p.images else None,
                unit=p.unit,
                times_bought=n,
                total_quantity=int(qty or 0),
                last_bought_at=last,
                price=p.retail_price if p.listed else None,
                in_stock=p.listed and p.stock > 0,
            )
        )
    return out


class CommentIn(BaseModel):
    text: str = Field(min_length=1, max_length=1000)


class CommentOut(BaseModel):
    id: int
    text: str
    from_staff: bool
    author: str
    created_at: datetime


async def _comments(session, order_id: int) -> list[CommentOut]:
    rows = await session.execute(
        select(OrderComment, User.full_name)
        .outerjoin(User, User.id == OrderComment.author_id)
        .where(OrderComment.order_id == order_id, OrderComment.channel == "shop")
        .order_by(OrderComment.created_at, OrderComment.id)
    )
    return [
        CommentOut(
            id=c.id,
            text=c.text,
            from_staff=c.from_staff,
            author="Магазин" if c.from_staff else (name or "Покупатель"),
            created_at=c.created_at,
        )
        for c, name in rows
    ]


async def my_order(session, user: User, order_id: int) -> Order:
    """Заказ покупателя. Чужой — как будто его нет (404), чтобы не раскрывать, что такой номер существует."""
    order = await session.get(Order, order_id)
    if order is None or order.user_id != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Order not found")
    return order


@router.get("/me/orders/{order_id}/comments", response_model=list[CommentOut])
async def my_order_comments(order_id: int, user: CurrentUser, session: SessionDep):
    await my_order(session, user, order_id)
    return await _comments(session, order_id)


@router.post("/me/orders/{order_id}/comments", response_model=list[CommentOut], status_code=201)
async def add_my_comment(order_id: int, body: CommentIn, user: CurrentUser, session: SessionDep):
    order = await my_order(session, user, order_id)
    if order.status in (OrderStatus.DELIVERED, OrderStatus.CANCELLED):
        raise HTTPException(status.HTTP_409_CONFLICT, "Order is closed")
    session.add(OrderComment(order_id=order.id, author_id=user.id, from_staff=False, text=body.text.strip()))
    await session.flush()
    return await _comments(session, order_id)


@router.get(
    "/admin/orders/{order_id}/comments",
    response_model=list[CommentOut],
    dependencies=[Depends(require(Permission.ORDERS_READ_ALL))],
)
async def order_comments_admin(order_id: int, session: SessionDep):
    return await _comments(session, order_id)


@router.post("/admin/orders/{order_id}/comments", response_model=list[CommentOut], status_code=201)
async def reply_comment(
    order_id: int,
    body: CommentIn,
    session: SessionDep,
    staff: Annotated[User, Depends(require(Permission.ORDERS_READ_ALL))],
):
    if await session.get(Order, order_id) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Order not found")
    session.add(OrderComment(order_id=order_id, author_id=staff.id, from_staff=True, text=body.text.strip()))
    await session.flush()
    return await _comments(session, order_id)
