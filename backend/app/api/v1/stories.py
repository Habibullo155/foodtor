from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import SessionDep, require
from app.models import Permission, Story, StorySlide

router = APIRouter(tags=["stories"])

# Картинки — только свои загрузки или https; ссылки кнопок — внутренние пути сайта или https
IMAGE = r"^(https://|/media/|/static/)"
LINK = r"^(/($|[^/\\])|https://)"


class SlideIn(BaseModel):
    image_url: str = Field(max_length=1024, pattern=IMAGE)
    headline: str = Field(min_length=1, max_length=120)
    caption: str | None = Field(default=None, max_length=300)
    cta_label: str | None = Field(default=None, max_length=40)
    cta_url: str | None = Field(default=None, max_length=300, pattern=LINK)

    @model_validator(mode="after")
    def _cta(self):
        if bool(self.cta_label) != bool(self.cta_url):
            raise ValueError("У кнопки нужны и текст, и ссылка")
        return self


class SlideOut(SlideIn):
    id: int


class StoryIn(BaseModel):
    title: str = Field(min_length=1, max_length=40)
    cover_url: str = Field(max_length=1024, pattern=IMAGE)
    color_hex: str = Field(default="#0B5D3B", pattern=r"^#[0-9A-Fa-f]{6}$")
    is_active: bool = True
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    slides: list[SlideIn] = Field(min_length=1, max_length=10)

    @model_validator(mode="after")
    def _dates(self):
        if self.starts_at and self.ends_at and self.ends_at <= self.starts_at:
            raise ValueError("Дата окончания должна быть позже даты начала")
        return self


class StoryOut(BaseModel):
    id: int
    title: str
    cover_url: str
    color_hex: str
    is_active: bool
    starts_at: datetime | None
    ends_at: datetime | None
    position: int
    slides: list[SlideOut]


def _out(s: Story) -> StoryOut:
    return StoryOut(
        id=s.id,
        title=s.title,
        cover_url=s.cover_url,
        color_hex=s.color_hex,
        is_active=s.is_active,
        starts_at=s.starts_at,
        ends_at=s.ends_at,
        position=s.position,
        slides=[
            SlideOut(
                id=x.id,
                image_url=x.image_url,
                headline=x.headline,
                caption=x.caption,
                cta_label=x.cta_label,
                cta_url=x.cta_url,
            )
            for x in s.slides
        ],
    )


async def visible_stories(session: AsyncSession) -> list[Story]:
    """Что видят покупатели: включённые и в сроках показа, по порядку."""
    now = datetime.now(UTC)
    rows = await session.scalars(
        select(Story)
        .where(
            Story.is_active,
            or_(Story.starts_at.is_(None), Story.starts_at <= now),
            or_(Story.ends_at.is_(None), Story.ends_at > now),
        )
        .order_by(Story.position, Story.id)
    )
    return [s for s in rows.all() if s.slides]


@router.get("/stories", response_model=list[StoryOut])
async def public_stories(session: SessionDep, response: Response):
    response.headers["Cache-Control"] = "public, max-age=60"
    return [_out(s) for s in await visible_stories(session)]


Guard = Depends(require(Permission.PRODUCTS_WRITE))


def _slides(body: StoryIn) -> list[StorySlide]:
    return [StorySlide(position=i, **sl.model_dump()) for i, sl in enumerate(body.slides)]


@router.get("/admin/stories", response_model=list[StoryOut], dependencies=[Guard])
async def admin_stories(session: SessionDep):
    rows = await session.scalars(select(Story).order_by(Story.position, Story.id))
    return [_out(s) for s in rows.all()]


@router.post("/admin/stories", response_model=StoryOut, status_code=201, dependencies=[Guard])
async def create_story(body: StoryIn, session: SessionDep):
    last = await session.scalar(select(Story.position).order_by(Story.position.desc()).limit(1))
    story = Story(**body.model_dump(exclude={"slides"}), position=(last or 0) + 1, slides=_slides(body))
    session.add(story)
    await session.flush()
    return _out(story)


async def _get(session, story_id: int) -> Story:
    story = await session.get(Story, story_id)
    if story is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Story not found")
    return story


@router.put("/admin/stories/{story_id}", response_model=StoryOut, dependencies=[Guard])
async def update_story(story_id: int, body: StoryIn, session: SessionDep):
    story = await _get(session, story_id)
    for k, v in body.model_dump(exclude={"slides"}).items():
        setattr(story, k, v)
    story.slides = _slides(body)  # слайды заменяются целиком — порядок как в редакторе
    await session.flush()
    return _out(story)


@router.delete("/admin/stories/{story_id}", status_code=204, dependencies=[Guard])
async def delete_story(story_id: int, session: SessionDep):
    await session.delete(await _get(session, story_id))


class OrderIn(BaseModel):
    ids: list[int] = Field(min_length=1, max_length=100)


@router.put("/admin/stories-order", response_model=list[StoryOut], dependencies=[Guard])
async def reorder_stories(body: OrderIn, session: SessionDep):
    """Порядок кружков: id в нужной последовательности."""
    stories = {s.id: s for s in (await session.scalars(select(Story).where(Story.id.in_(body.ids)))).all()}
    for pos, sid in enumerate(body.ids):
        if sid in stories:
            stories[sid].position = pos
    await session.flush()
    rows = await session.scalars(select(Story).order_by(Story.position, Story.id))
    return [_out(s) for s in rows.all()]
