"""Настоящие фото товаров и категорий из фотобанка Pexels (бесплатно, можно в магазине без указания автора).

Ключ: https://www.pexels.com/api/ → «Get started» (бесплатно, сразу после регистрации).

    PEXELS_API_KEY=... python -m scripts.fetch_photos            # только товары и категории без фото или с картинкой-заглушкой
    PEXELS_API_KEY=... python -m scripts.fetch_photos --all      # заменить фото у всех

Фото, загруженные вручную в админке или через Excel, без --all не трогаются.
"""

import argparse
import asyncio
import os
import sys

import httpx
from sqlalchemy import select

from app.db.session import SessionFactory
from app.models import Banner, Category, Product, ProductImage
from app.services import images

API = "https://api.pexels.com/v1/search"
PLACEHOLDER = "/static/catalog/"  # картинки стартового каталога — их и меняем на фото

# Что искать: первое совпадение по началу или вхождению в название (порядок важен — частное раньше общего)
QUERIES = [
    # эти названия содержат более общие слова (лимон-ад, ман-го-стин, фа-соль, слив-очное) — проверяем их первыми
    ("помидоры сливовидные", "plum tomatoes"),
    ("масло сливочное", "butter"),
    ("кетчуп", "ketchup"),
    ("печенье", "oatmeal cookies"),
    ("сок апельсин", "orange juice"),
    ("сок яблоч", "apple juice"),
    ("лимонад", "lemonade"),
    ("фасоль в томат", "baked beans"),
    ("фасоль", "red kidney beans"),
    ("мангостин", "mangosteen"),
    ("мангольд", "swiss chard"),
    ("гренни смит", "green granny smith apples"),
    ("симиренко", "green apples"),
    ("голден", "golden yellow apples"),
    ("яблоки сушёные", "dried apple rings"),
    ("яблок", "red apples"),
    ("груша сушёная", "dried pears"),
    ("груш", "pears fruit"),
    ("бананы сушёные", "dried banana chips"),
    ("банан", "bananas"),
    ("виноград киш-миш зелёный", "green grapes"),
    ("виноград шайн", "green grapes"),
    ("виноград", "grapes bunch"),
    ("нектарин", "nectarines"),
    ("персик", "peaches"),
    ("слив", "plums"),
    ("гранат", "pomegranate"),
    ("хурма сушёная", "dried persimmon"),
    ("хурм", "persimmon"),
    ("айва", "quince fruit"),
    ("фейхоа", "feijoa"),
    ("инжир сушёный", "dried figs"),
    ("инжир", "fresh figs"),
    ("арбуз", "watermelon"),
    ("дыня", "melon"),
    ("клубника в", "chocolate covered strawberries"),
    ("клубник", "strawberries"),
    ("малин", "raspberries"),
    ("голубик", "blueberries"),
    ("апельсин", "oranges"),
    ("мандарины с листьями", "tangerines with leaves"),
    ("мандарин", "tangerines"),
    ("лимон", "lemons"),
    ("лайм", "limes"),
    ("грейпфрут", "grapefruit"),
    ("помело", "pomelo"),
    ("манго сушёное", "dried mango"),
    ("манго", "mango fruit"),
    ("авокадо", "avocado"),
    ("ананас сушёный", "dried pineapple"),
    ("ананас", "pineapple"),
    ("кокос", "coconut"),
    ("маракуй", "passion fruit"),
    ("питахай", "dragon fruit"),
    ("лонган", "longan fruit"),
    ("папай", "papaya"),
    ("джекфрут", "jackfruit"),
    ("киви сушёное", "dried kiwi"),
    ("черри", "cherry tomatoes"),
    ("томаты жёлтые", "yellow tomatoes"),
    ("томаты кумато", "black tomatoes"),
    ("томатная", "tomato paste"),
    ("томаты в собственном", "canned tomatoes"),
    ("помидор", "tomatoes"),
    ("томат", "tomatoes"),
    ("корнишон", "small pickling cucumbers"),
    ("огурц", "cucumbers"),
    ("батат", "sweet potatoes"),
    ("картофел", "potatoes"),
    ("морковь жёлтая", "yellow carrots"),
    ("морков", "carrots"),
    ("свёкла", "beetroot"),
    ("лук-порей", "leek"),
    ("лук зелёный", "green onions"),
    ("лук красный", "red onions"),
    ("лук ялтинский", "red onions"),
    ("лук бел", "white onions"),
    ("лук", "onions"),
    ("чеснок", "garlic"),
    ("имбир", "ginger root"),
    ("кабачк", "zucchini"),
    ("цукини", "zucchini"),
    ("баклажан", "eggplant"),
    ("перец сладкий жёлтый", "yellow bell pepper"),
    ("перец мини", "mini sweet peppers"),
    ("перец сладкий", "red bell pepper"),
    ("перец острый зелёный", "green chili peppers"),
    ("перец острый", "red chili peppers"),
    ("халапеньо", "jalapeno"),
    ("брокколи", "broccoli"),
    ("капуста цветная", "cauliflower"),
    ("капуста пекинская", "napa cabbage"),
    ("капуста пак-чой", "bok choy"),
    ("капуста брюссельская", "brussels sprouts"),
    ("капуста", "cabbage"),
    ("дайкон", "daikon radish"),
    ("редис", "radishes"),
    ("кукуруза сладкая", "canned corn"),
    ("кукуруза", "corn cob"),
    ("сельдерей", "celery stalks"),
    ("шампиньон", "champignon mushrooms"),
    ("шиитаке", "shiitake mushrooms"),
    ("эноки", "enoki mushrooms"),
    ("шимеджи", "shimeji mushrooms"),
    ("укроп", "fresh dill"),
    ("петрушк", "fresh parsley"),
    ("кинз", "fresh cilantro"),
    ("щавел", "sorrel leaves"),
    ("шпинат", "fresh spinach"),
    ("базилик", "purple basil"),
    ("мят", "fresh mint"),
    ("розмарин", "fresh rosemary"),
    ("руккол", "arugula"),
    ("айсберг", "iceberg lettuce"),
    ("салатная смесь", "mixed salad leaves"),
    ("миндаль", "almonds"),
    ("грецкий", "walnuts"),
    ("фундук", "hazelnuts"),
    ("кешью", "cashew nuts"),
    ("фисташк", "pistachios"),
    ("бразильский", "brazil nuts"),
    ("макадамия", "macadamia nuts"),
    ("арахис", "peanuts"),
    ("семечки", "sunflower seeds"),
    ("кунжут чёрный", "black sesame seeds"),
    ("кунжут", "sesame seeds"),
    ("финики", "dates fruit"),
    ("курага", "dried apricots"),
    ("компотная", "dried fruit mix"),
    ("мёд", "honey jar"),
    ("гречк", "buckwheat"),
    ("рис", "rice grains"),
    ("пшено", "millet grains"),
    ("овсян", "oat flakes"),
    ("спагетти", "spaghetti pasta"),
    ("макароны", "penne pasta"),
    ("мука", "flour"),
    ("сахар", "sugar"),
    ("соль", "salt"),
    ("чечевиц", "red lentils"),
    ("нут", "chickpeas"),
    ("масло подсолнечное", "sunflower oil bottle"),
    ("масло оливковое", "olive oil bottle"),
    ("уксус", "apple cider vinegar"),
    ("соус соевый", "soy sauce"),
    ("майонез", "mayonnaise"),
    ("горошек", "green peas"),
    ("тунец", "canned tuna"),
    ("оливки", "green olives"),
    ("чай чёрный", "black tea"),
    ("чай зелёный", "green tea leaves"),
    ("кофе в зёрнах", "coffee beans"),
    ("кофе", "ground coffee"),
    ("какао", "cocoa powder"),
    ("шоколад", "chocolate bar"),
    ("мармелад", "fruit jelly candies"),
    ("вафли", "wafers"),
    ("зефир", "marshmallow"),
    ("вода питьевая", "water bottle"),
    ("вода минеральная", "mineral water bottle"),
    ("морс", "cranberry juice"),
    ("молоко", "milk bottle"),
    ("кефир", "kefir"),
    ("сметана", "sour cream"),
    ("творог", "cottage cheese"),
    ("сыр", "cheese"),
    ("яйца", "eggs"),
    ("хлеб бородинский", "rye bread"),
    ("хлеб", "white bread loaf"),
    ("багет", "baguette"),
    ("лаваш", "lavash flatbread"),
    ("круассан", "croissant"),
    ("для мытья посуды", "dish soap"),
    ("стиральный", "laundry detergent"),
    ("мыло", "liquid soap"),
    ("чистящее", "cleaning spray bottle"),
    ("губки", "kitchen sponges"),
    ("туалетная", "toilet paper"),
    ("полотенца", "paper towels"),
    ("салфетки", "paper napkins"),
    ("пакеты для мусора", "garbage bags"),
    ("свечи", "white candles"),
]

CATEGORY_QUERIES = {
    "frukty": "fresh fruits assortment",
    "yagody": "fresh berries",
    "tsitrusovye": "citrus fruits",
    "ekzotika": "tropical fruits",
    "ovoschi": "fresh vegetables",
    "griby": "mushrooms",
    "zelen": "fresh herbs",
    "orehi": "mixed nuts",
    "suhofrukty": "dried fruits",
    "med": "honey jar",
    "bakaleya": "grains and pasta",
    "maslo-i-sousy": "olive oil and sauces",
    "konservy": "canned food",
    "chay-i-kofe": "coffee and tea",
    "sladosti": "sweets and chocolate",
    "napitki": "juice bottles",
    "molochnoe": "dairy products",
    "hleb": "fresh bread",
    "bytovaya-himiya": "cleaning products",
    "dlya-doma": "household paper products",
}

BANNER_QUERIES = ["fresh fruits market", "fresh vegetables", "tropical fruits", "honey"]


def query_for(name: str) -> str | None:
    low = name.lower()
    return next((q for key, q in QUERIES if key in low), None)


class Pexels:
    def __init__(self, key: str) -> None:
        self.http = httpx.AsyncClient(headers={"Authorization": key}, timeout=20)
        self.cache: dict[tuple[str, str], list[str]] = {}

    async def urls(self, query: str, orientation: str = "square") -> list[str]:
        """Адреса фото по запросу, уже обрезанные под нужный формат силами CDN Pexels."""
        if (query, orientation) not in self.cache:
            r = await self.http.get(API, params={"query": query, "per_page": 15, "orientation": orientation})
            if r.status_code == 429:
                sys.exit("Pexels: превышен лимит запросов (200 в час) — запустите скрипт ещё раз через час")
            r.raise_for_status()
            size = "w=1200&h=1200" if orientation == "square" else "w=1600&h=1000"
            self.cache[(query, orientation)] = [
                f"{p['src']['original']}?auto=compress&cs=tinysrgb&fit=crop&{size}" for p in r.json()["photos"]
            ]
        return self.cache[(query, orientation)]

    async def pick(self, query: str, used: dict[str, int], orientation: str = "square") -> str | None:
        """Разные товары с одинаковым запросом (сорта томатов) получают разные фото."""
        urls = await self.urls(query, orientation)
        n = used.get(query, 0)
        used[query] = n + 1
        return urls[n % len(urls)] if urls else None


async def store(url: str, folder: str) -> str | None:
    try:
        path, _, _ = images.store(await images.download(url), folder)
    except (images.ImageError, OSError, httpx.HTTPError) as exc:
        print(f"  не скачалось: {exc}")
        return None
    return path


def replaceable(url: str | None, everything: bool) -> bool:
    return everything or not url or url.startswith(PLACEHOLDER)


async def run(everything: bool) -> None:
    key = os.environ.get("PEXELS_API_KEY", "").strip()
    if not key:
        sys.exit("Укажите ключ: PEXELS_API_KEY=... (бесплатно на https://www.pexels.com/api/)")
    px = Pexels(key)
    used: dict[str, int] = {}
    done = skipped = 0
    async with SessionFactory() as s:
        for c in (await s.scalars(select(Category))).all():
            q = CATEGORY_QUERIES.get(c.slug)
            if q and replaceable(c.image_url, everything) and (url := await px.pick(q, used)):
                if path := await store(url, "products"):
                    c.image_url = path
                    done += 1
        await s.commit()

        for p in (await s.scalars(select(Product).order_by(Product.id))).unique().all():
            current = p.images[0].url if p.images else None
            if not replaceable(current, everything):
                continue
            q = query_for(p.name)
            if q is None:
                print(f"  нет запроса для «{p.name}» — пропускаю")
                skipped += 1
                continue
            if (url := await px.pick(q, used)) and (path := await store(url, "products")):
                p.images = [ProductImage(url=path, position=0)]
                done += 1
                await s.commit()  # по одному: при обрыве не теряем уже скачанное
                print(f"  ✓ {p.name}")

        for b, q in zip((await s.scalars(select(Banner).order_by(Banner.position))).all(), BANNER_QUERIES, strict=False):
            if replaceable(b.image_url, everything) and (url := await px.pick(q, used, "landscape")):
                if path := await store(url, "banners"):
                    b.image_url = path
                    done += 1
        await s.commit()
    await px.http.aclose()
    print(f"Готово: фото обновлено у {done}, без запроса: {skipped}. Фото — Pexels (pexels.com/license)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--all", action="store_true", help="заменить фото у всех товаров, а не только у заглушек")
    asyncio.run(run(parser.parse_args().all))


if __name__ == "__main__":
    main()
