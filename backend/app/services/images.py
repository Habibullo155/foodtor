import io
import ipaddress
import secrets
import socket
from pathlib import Path
from urllib.parse import urlparse

import httpx
from PIL import Image, ImageOps, UnidentifiedImageError

from app.core.config import get_settings

STATIC = Path(__file__).resolve().parents[1] / "web" / "static"
MAX_BYTES = 10 * 1024 * 1024
MIN_SIDE = 300  # меньше — на карточке будет мыльно
MAX_SIDE = {"products": 1200, "banners": 1800}

Image.MAX_IMAGE_PIXELS = 40_000_000  # «бомба» из миллиардов пикселей отклоняется до декодирования


class ImageError(ValueError):
    pass


def process(raw: bytes, max_side: int = 1200) -> tuple[bytes, int, int]:
    """Проверка, поворот по EXIF, уменьшение, WebP без метаданных. Прозрачный фон сохраняется."""
    try:
        img = Image.open(io.BytesIO(raw))
        img.verify()
        img = ImageOps.exif_transpose(Image.open(io.BytesIO(raw)))
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError) as exc:
        raise ImageError("Это не изображение — загрузите JPG, PNG или WebP") from exc
    if min(img.size) < MIN_SIDE:
        raise ImageError(
            f"Фото слишком маленькое ({img.width}×{img.height}). Нужно от {MIN_SIDE}×{MIN_SIDE} px, лучше 1000×1000"
        )
    img = img.convert("RGBA" if img.mode in ("RGBA", "LA", "P") else "RGB")
    img.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
    out = io.BytesIO()
    img.save(out, "WEBP", quality=85, method=6)
    return out.getvalue(), img.width, img.height


def store(raw: bytes, folder: str = "products") -> tuple[str, int, int]:
    data, w, h = process(raw, MAX_SIDE.get(folder, 1200))
    s = get_settings()
    target = Path(s.media_root) / folder
    target.mkdir(parents=True, exist_ok=True)
    name = f"{secrets.token_hex(12)}.webp"
    (target / name).write_bytes(data)
    return f"{s.media_url}/{folder}/{name}", w, h


def is_own(url: str) -> bool:
    """Фото уже на нашем сервере: /media/…, /static/…, адрес нашего сайта — или файл из нашей папки фото
    (адрес сервера на своём компьютере меняется при каждом запуске, а файлы остаются)."""
    s = get_settings()
    if url.startswith(("/media/", "/static/")):
        return True
    parsed = urlparse(url)
    if parsed.hostname in {urlparse(s.public_shop_url).hostname, urlparse(s.public_api_url).hostname}:
        return True
    for prefix, root in ((s.media_url.rstrip("/") + "/", Path(s.media_root)), ("/static/", STATIC)):
        if parsed.path.startswith(prefix):
            local = (root / parsed.path.removeprefix(prefix)).resolve()
            return local.is_file() and root.resolve() in local.parents
    return False


def _public_host(host: str) -> bool:
    # защита от SSRF: по ссылке из файла сервер не должен ходить во внутреннюю сеть
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    return all(ipaddress.ip_address(info[4][0]).is_global for info in infos)


async def download(url: str) -> bytes:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname or not _public_host(parsed.hostname):
        raise ImageError("Ссылка на фото должна вести на открытый сайт (http/https)")
    async with httpx.AsyncClient(timeout=15, follow_redirects=False) as client:
        async with client.stream("GET", url, headers={"User-Agent": "FOODTOR image import"}) as r:
            if r.status_code != 200:
                raise ImageError(f"Фото не скачалось (ответ {r.status_code})")
            data = bytearray()
            async for chunk in r.aiter_bytes():
                data += chunk
                if len(data) > MAX_BYTES:
                    raise ImageError("Фото больше 10 МБ")
    return bytes(data)
