"""Рисует картинки стартового каталога в app/web/static/catalog из эмодзи Noto (Apache 2.0).

Запускается на своём компьютере, нужен интернет:  python -m scripts.catalog_art
Готовые WebP лежат в репозитории, на сервере скрипт не нужен.
"""

import hashlib
from pathlib import Path

import httpx
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from scripts.foodtor_catalog import BANNERS, CATEGORIES, FRESH, HIDDEN

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "app" / "web" / "static" / "catalog"
CACHE = ROOT / ".emoji-cache"
NOTO = "https://fonts.gstatic.com/s/e/notoemoji/latest/{code}/512.png"
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"

# Пастельные пары (светлый, насыщенный) — у каждой категории свой цвет
PALETTE = {
    "frukty": ("#FFE3DC", "#F26B4F"),
    "yagody": ("#FFE0E8", "#E0446A"),
    "tsitrusovye": ("#FFF0CC", "#F59E0B"),
    "ekzotika": ("#FFF4D6", "#E8A317"),
    "ovoschi": ("#FFE8D6", "#EA7A2E"),
    "griby": ("#F1E7DC", "#9C6B47"),
    "zelen": ("#DFF5E3", "#2F9E55"),
    "orehi": ("#F5E9D7", "#B07A3B"),
    "suhofrukty": ("#FBE6D3", "#C7702E"),
    "med": ("#FFF1C7", "#E0A100"),
    "bakaleya": ("#F3EEE2", "#A8874E"),
    "maslo-i-sousy": ("#EEF4D8", "#7E9A2B"),
    "konservy": ("#FDE4E1", "#C9473B"),
    "chay-i-kofe": ("#EFE5DD", "#7B4E34"),
    "sladosti": ("#F7E3EE", "#B54A80"),
    "napitki": ("#DDF1F7", "#2B93B5"),
    "molochnoe": ("#E6EEF8", "#4F7BB8"),
    "hleb": ("#F8EBD8", "#C18534"),
    "bytovaya-himiya": ("#E3F0FB", "#3B82C4"),
    "dlya-doma": ("#ECE8F7", "#6E5BB0"),
}

# Плитка категории: какие эмодзи и в каком порядке (первый — крупный, по центру)
TILE = {
    "frukty": ["1f34e", "1f350", "1f34c"],
    "yagody": ["1f353", "1fad0", "1f352"],
    "tsitrusovye": ["1f34a", "1f34b", "1f34b_200d_1f7e9"],
    "ekzotika": ["1f96d", "1f34d", "1f951"],
    "ovoschi": ["1f955", "1f345", "1f952"],
    "griby": ["1f344_200d_1f7eb", "1f344_200d_1f7eb"],
    "zelen": ["1f96c", "1f33f", "1f966"],
    "orehi": ["1f95c", "1f330"],
    "suhofrukty": ["1f330", "1f347", "1f96d"],
    "med": ["1f36f", "1f41d"],
    "bakaleya": ["1f35a", "1f33e", "1f35d"],
    "maslo-i-sousy": ["1fad2", "1f345"],
    "konservy": ["1f96b", "1fadb"],
    "chay-i-kofe": ["2615", "1f375"],
    "sladosti": ["1f36b", "1f36a", "1f36c"],
    "napitki": ["1f9c3", "1f964"],
    "molochnoe": ["1f95b", "1f9c0", "1f95a"],
    "hleb": ["1f35e", "1f950", "1f956"],
    "bytovaya-himiya": ["1f9f4", "1f9fd", "1f9fc"],
    "dlya-doma": ["1f9fb", "1f56f"],
}

# Мелкое на развес рисуем горкой из трёх штук
SMALL = {"1f34e", "1f34f", "1f350", "1f34a", "1f34b", "1f351", "1f345", "1f954", "1f9c5", "1f9c4", "1f95c", "1f330",
         "1f344_200d_1f7eb", "1f955", "1f952", "1fad1", "1f336", "1f360"}


def emoji(code: str) -> Image.Image:
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f"{code}.png"
    if not path.exists():
        r = httpx.get(NOTO.format(code=code), timeout=30, follow_redirects=True)
        r.raise_for_status()
        path.write_bytes(r.content)
    return Image.open(path).convert("RGBA")


def rgb(hex_: str) -> tuple[int, int, int]:
    return tuple(int(hex_[i : i + 2], 16) for i in (1, 3, 5))


def with_shadow(img: Image.Image, opacity: float = 0.22) -> Image.Image:
    """Мягкая тень под предметом: размытая тёмная копия силуэта, сдвинутая вниз."""
    pad = img.width // 6
    canvas = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), (0, 0, 0, 0))
    alpha = img.getchannel("A").point(lambda a: int(a * opacity))
    shadow = Image.new("RGBA", img.size, (40, 30, 20, 0))
    shadow.putalpha(alpha)
    canvas.alpha_composite(shadow, (pad, pad + img.height // 16))
    canvas = canvas.filter(ImageFilter.GaussianBlur(img.width // 28))
    canvas.alpha_composite(img, (pad, pad))
    return canvas


def place(canvas: Image.Image, code: str, size: int, center: tuple[float, float], angle: float = 0) -> None:
    item = emoji(code).resize((size, size), Image.Resampling.LANCZOS)
    if angle:
        item = item.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    item = with_shadow(item)
    canvas.alpha_composite(item, (int(center[0] - item.width / 2), int(center[1] - item.height / 2)))


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "WEBP", quality=88, method=4)


def product_single(code: str) -> Image.Image:
    c = Image.new("RGBA", (800, 800), (0, 0, 0, 0))
    place(c, code, 560, (400, 410))
    return c


def product_trio(code: str) -> Image.Image:
    c = Image.new("RGBA", (800, 800), (0, 0, 0, 0))
    place(c, code, 400, (270, 330), -14)
    place(c, code, 400, (540, 320), 12)
    place(c, code, 440, (400, 500), 0)
    return c


def placeholder(name: str, slug: str) -> Image.Image:
    """Нет подходящей картинки — аккуратная плитка с буквой и значком категории."""
    light, deep = PALETTE[slug]
    c = Image.new("RGBA", (800, 800), (0, 0, 0, 0))
    disc = Image.new("RGBA", (800, 800), (0, 0, 0, 0))
    d = ImageDraw.Draw(disc)
    d.ellipse((100, 100, 700, 700), fill=rgb(light) + (255,))
    c.alpha_composite(disc)
    font = ImageFont.truetype(FONT, 300)
    letter = name[0].upper()
    box = ImageDraw.Draw(c).textbbox((0, 0), letter, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    ImageDraw.Draw(c).text((400 - w / 2 - box[0], 390 - h / 2 - box[1]), letter, font=font, fill=rgb(deep) + (255,))
    place(c, TILE[slug][0], 190, (600, 600), 8)
    return c


def category_tile(slug: str) -> Image.Image:
    light, deep = PALETTE[slug]
    size = 600
    a, b = rgb(light), rgb(deep)
    # диагональный градиент: от светлого цвета категории к чуть более насыщенному
    mask = Image.linear_gradient("L").resize((size * 2, size * 2)).rotate(45).crop(
        (size // 2, size // 2, size * 3 // 2, size * 3 // 2)
    )
    deeper = tuple(int(a[i] + (b[i] - a[i]) * 0.25) for i in range(3))
    c = Image.composite(Image.new("RGB", (size, size), deeper), Image.new("RGB", (size, size), a), mask).convert("RGBA")
    glow = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    ImageDraw.Draw(glow).ellipse((60, 40, 480, 420), fill=(255, 255, 255, 120))
    c.alpha_composite(glow.filter(ImageFilter.GaussianBlur(50)))
    codes = TILE[slug]
    if len(codes) >= 3:
        place(c, codes[1], 230, (175, 250), -16)
        place(c, codes[2], 230, (430, 240), 14)
    elif len(codes) == 2:
        place(c, codes[1], 240, (420, 225), 14)
    place(c, codes[0], 330, (size / 2 - (20 if len(codes) == 2 else 0), 380))
    return c


def banner(codes: list[str]) -> Image.Image:
    c = Image.new("RGBA", (1400, 900), (0, 0, 0, 0))
    n = len(codes)
    if n <= 3:
        spots = [(700, 480, 560, 0), (330, 330, 360, -12), (1070, 360, 340, 12)]
    else:
        spots = [(700, 520, 520, 0), (330, 300, 360, -14), (1070, 290, 360, 12), (300, 640, 300, 10), (1110, 650, 300, -10)]
    # дальние рисуем первыми, главный — поверх
    order = list(range(1, n)) + [0]
    for i in order:
        x, y, s, ang = spots[i]
        place(c, codes[i], s, (x, y), ang)
    return c


def share_image() -> Image.Image:
    """Превью ссылки в мессенджерах и соцсетях (og:image), 1200×630."""
    c = Image.new("RGBA", (1200, 630), rgb("#0B5D3B") + (255,))
    glow = Image.new("RGBA", c.size, (255, 255, 255, 0))
    ImageDraw.Draw(glow).ellipse((620, 40, 1260, 680), fill=(255, 255, 255, 40))
    c.alpha_composite(glow.filter(ImageFilter.GaussianBlur(60)))
    for code, size, xy, ang in (
        ("1f350", 220, (760, 200), -12),
        ("1f347", 220, (1060, 190), 12),
        ("1f34a", 190, (740, 460), 10),
        ("1f34c", 200, (1080, 470), -10),
        ("1f34e", 300, (910, 360), 0),
    ):
        place(c, code, size, xy, ang)
    d = ImageDraw.Draw(c)
    d.text((70, 170), "FOOD", font=ImageFont.truetype(FONT, 96), fill=(255, 255, 255))
    food_w = d.textlength("FOOD", font=ImageFont.truetype(FONT, 96))
    d.text((70 + food_w, 170), "TOR", font=ImageFont.truetype(FONT, 96), fill=rgb("#FFA726"))
    small = ImageFont.truetype(FONT, 40)
    d.text((72, 310), "Свежие фрукты и овощи", font=small, fill=(255, 255, 255))
    d.text((72, 362), "с доставкой на дом", font=small, fill=(255, 255, 255))
    d.text((72, 470), "foodtor.ru", font=ImageFont.truetype(FONT, 30), fill=(255, 255, 255, 170))
    return c.convert("RGB")


def fresh_image_name(name: str) -> str:
    return "p/" + hashlib.sha256(name.encode()).hexdigest()[:10] + ".webp"


def product_image(name: str, unit: str, code: str | None, slug: str) -> str:
    """Путь картинки товара относительно /static/catalog/."""
    if code is None:
        return fresh_image_name(name)
    trio = code in SMALL and unit.endswith("кг")
    return f"p/{code}{'-3' if trio else ''}.webp"


def main() -> None:
    made: set[str] = set()
    for slug, *_ in CATEGORIES:
        save(category_tile(slug), OUT / "c" / f"{slug}.webp")
    for groups in (FRESH, HIDDEN):
        for slug, items in groups.items():
            for name, _price, unit, code in items:
                rel = product_image(name, unit, code, slug)
                if rel in made:
                    continue
                made.add(rel)
                if code is None:
                    img = placeholder(name, slug)
                elif rel.endswith("-3.webp"):
                    img = product_trio(code)
                else:
                    img = product_single(code)
                save(img, OUT / rel)
    for i, (*_, codes) in enumerate(BANNERS, 1):
        save(banner(codes), OUT / "b" / f"{i}.webp")
    share_image().save(OUT / "og.jpg", "JPEG", quality=88, optimize=True)
    print(f"Готово: {len(made)} картинок товаров, {len(CATEGORIES)} категорий, {len(BANNERS)} баннеров → {OUT}")


if __name__ == "__main__":
    main()
