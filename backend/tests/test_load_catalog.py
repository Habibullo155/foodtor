from pathlib import Path

from sqlalchemy import func, select

from app.models import Banner, Category, Product
from scripts.foodtor_catalog import FRESH, HIDDEN, our_price
from scripts.load_catalog import load
from tests import factories as f

STATIC = Path(__file__).resolve().parents[1] / "app" / "web" / "static"


def test_price_rule():
    assert our_price(950) == 650  # дорогое — на 300 ₽ дешевле
    assert our_price(160) == 139  # дешёвое — на 10%, с «девяткой»
    assert our_price(90) == 79
    assert our_price(39) == 29


async def test_replace_loads_catalog_with_hidden_groceries(client, db):
    await f.product(db, "Старый товар")
    await db.commit()

    added = await load(db, replace=True)
    await db.commit()
    total = sum(len(v) for v in FRESH.values()) + sum(len(v) for v in HIDDEN.values())
    assert added == total == await db.scalar(select(func.count()).select_from(Product))
    assert not await db.scalar(select(Product.id).where(Product.name == "Старый товар"))
    assert await db.scalar(select(func.count()).select_from(Banner)) == 4

    # все картинки, на которые ссылается каталог, лежат в репозитории
    urls = list(await db.scalars(select(Category.image_url))) + list(await db.scalars(select(Banner.image_url)))
    products = (await db.scalars(select(Product))).unique().all()
    urls += [p.images[0].url for p in products]
    missing = {u for u in urls if not (STATIC / u.removeprefix("/static/")).is_file()}
    assert not missing

    names = [c["name"] for c in (await client.get("/api/v1/categories")).json()]
    assert "Фрукты" in names and "Бакалея" not in names
    found = (await client.get("/api/v1/products", params={"q": "Гречка"})).json()["items"]
    assert found == []

    assert await load(db, replace=False) == 0  # повторный запуск ничего не дублирует
