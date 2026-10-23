"""Загружает стартовый каталог FOODTOR (scripts/foodtor_catalog.py) в базу.

    python -m scripts.load_catalog            # добавить недостающее, существующее не трогать
    python -m scripts.load_catalog --replace  # сначала удалить ВСЕ товары, категории и баннеры

На сервере:
    docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env exec api python -m scripts.load_catalog --replace

Товары без себестоимости (0) — заполните её через «Выгрузить в Excel» → «Загрузить Excel».
"""

import argparse
import asyncio

from sqlalchemy import delete, select

from app.db.session import SessionFactory
from app.models import Banner, Category, Product, ProductImage
from scripts.catalog_art import product_image
from scripts.foodtor_catalog import BANNERS, CATEGORIES, FRESH, HIDDEN, HITS, our_price

STATIC = "/static/catalog/"
STOCK = 50


async def load(s, replace: bool) -> int:
    """Возвращает, сколько товаров добавлено. Коммит — на вызывающем."""
    if replace:
        # позиции заказов остаются: у них свои снимки названия и цены (FK → NULL)
        await s.execute(delete(Product))
        await s.execute(delete(Category))
        await s.execute(delete(Banner))

    cats = {c.slug: c for c in (await s.scalars(select(Category))).all()}
    for pos, (slug, name, _code, visible) in enumerate(CATEGORIES):
        if slug not in cats:
            cats[slug] = Category(
                slug=slug, name=name, position=pos, is_visible=visible, image_url=f"{STATIC}c/{slug}.webp"
            )
            s.add(cats[slug])
    await s.flush()

    existing = {p.name.lower() for p in (await s.scalars(select(Product))).unique().all()}
    added, n = 0, 0
    for prices_are_competitors, groups in ((True, FRESH), (False, HIDDEN)):
        for slug, items in groups.items():
            for name, price, unit, code in items:
                n += 1
                if name.lower() in existing:
                    continue
                s.add(
                    Product(
                        sku=f"FT-{n:04d}",
                        name=name,
                        unit=unit,
                        description="",
                        cost_price=0,
                        retail_price=our_price(price) if prices_are_competitors else price,
                        stock=STOCK,
                        is_hit=name in HITS,
                        category_id=cats[slug].id,
                        images=[ProductImage(url=STATIC + product_image(name, unit, code, slug), position=0)],
                    )
                )
                added += 1

    if replace or not await s.scalar(select(Banner.id).limit(1)):
        for pos, (title, text, label, link, theme, color, _codes) in enumerate(BANNERS):
            s.add(
                Banner(
                    title=title,
                    text=text,
                    image_url=f"{STATIC}b/{pos + 1}.webp",
                    button_label=label,
                    link_url=link,
                    theme=theme,
                    button_color=color,
                    position=pos,
                )
            )
    await s.flush()
    return added


async def run(replace: bool) -> None:
    async with SessionFactory() as s:
        added = await load(s, replace)
        await s.commit()
    visible = sum(1 for *_, v in CATEGORIES if v)
    print(f"Категорий: {len(CATEGORIES)} (на сайте {visible}), новых товаров: {added}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--replace", action="store_true", help="удалить все товары, категории и баннеры перед загрузкой")
    asyncio.run(run(parser.parse_args().replace))


if __name__ == "__main__":
    main()
