import io

from PIL import Image

from app.core.config import get_settings
from app.models import SystemRole
from tests.test_release_flows import shop, staff


def _png(w, h, alpha=False) -> bytes:
    img = Image.new("RGBA" if alpha else "RGB", (w, h), (200, 50, 50, 0) if alpha else (200, 50, 50))
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


async def test_upload_product_image(client, db, tmp_path, monkeypatch):
    monkeypatch.setattr(get_settings(), "media_root", str(tmp_path))
    tomato, _ = await shop(db)
    owner = await staff(client, db, SystemRole.OWNER, "owner-img@test.ru")
    picker = await staff(client, db, SystemRole.PICKER, "picker-img@test.ru")
    url = "/api/v1/admin/uploads/product-image"

    assert (await client.post(url, headers=picker, files={"file": ("a.png", _png(800, 800))})).status_code == 403
    small = await client.post(url, headers=owner, files={"file": ("a.png", _png(120, 120))})
    assert small.status_code == 422 and "300×300" in small.json()["detail"]
    junk = await client.post(url, headers=owner, files={"file": ("a.png", b"not an image")})
    assert junk.status_code == 422

    r = await client.post(url, headers=owner, files={"file": ("big.png", _png(3000, 2000, alpha=True))})
    assert r.status_code == 201
    out = r.json()
    assert out["url"].startswith("/media/products/") and out["url"].endswith(".webp")
    assert (out["width"], out["height"]) == (1200, 800)  # уменьшено с сохранением пропорций
    saved = Image.open(tmp_path / "products" / out["url"].rsplit("/", 1)[1])
    assert saved.format == "WEBP" and saved.mode == "RGBA"  # прозрачный фон сохранён

    patch = await client.patch(f"/api/v1/admin/products/{tomato.id}", headers=owner, json={"image_url": out["url"]})
    assert patch.status_code == 200 and patch.json()["image_url"] == out["url"]
    bad = await client.patch(f"/api/v1/admin/products/{tomato.id}", headers=owner, json={"image_url": "/etc/passwd"})
    assert bad.status_code == 422
