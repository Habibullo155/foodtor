from datetime import UTC, datetime, timedelta

from app.models import SystemRole
from tests.test_release_flows import register, staff

SLIDE = {
    "image_url": "/static/demo/strawberries.webp",
    "headline": "Клубника −20%",
    "caption": "Собрана вчера",
    "cta_label": "Смотреть ягоды",
    "cta_url": "/catalog/yagody",
}


def story(**kw):
    return {
        "title": "Сезон ягод",
        "cover_url": "/static/demo/strawberries.webp",
        "color_hex": "#E11D48",
        "slides": [SLIDE],
    } | kw


async def test_admin_manages_stories_and_site_shows_them(client, db):
    manager = await staff(client, db, SystemRole.MANAGER, "manager-st@test.ru")
    picker = await staff(client, db, SystemRole.PICKER, "picker-st@test.ru")
    buyer = await register(client)
    url = "/api/v1/admin/stories"

    assert (await client.post(url, headers=picker, json=story())).status_code == 403
    assert (await client.post(url, headers=buyer, json=story())).status_code == 403
    a = (await client.post(url, headers=manager, json=story())).json()
    b = (
        await client.post(
            url, headers=manager, json=story(title="Фермерское", slides=[SLIDE, SLIDE | {"headline": "2"}])
        )
    ).json()
    hidden = (await client.post(url, headers=manager, json=story(title="Скрытая", is_active=False))).json()
    future = (
        await client.post(
            url,
            headers=manager,
            json=story(title="Скоро", starts_at=(datetime.now(UTC) + timedelta(days=1)).isoformat()),
        )
    ).json()

    public = (await client.get("/api/v1/stories")).json()
    assert [s["title"] for s in public] == ["Сезон ягод", "Фермерское"]  # выключенная и будущая — не видны
    assert public[1]["slides"][1]["headline"] == "2"

    # порядок: Фермерское первым
    order = (
        await client.put(
            "/api/v1/admin/stories-order", headers=manager, json={"ids": [b["id"], a["id"], hidden["id"], future["id"]]}
        )
    ).json()
    assert [s["title"] for s in order][:2] == ["Фермерское", "Сезон ягод"]
    assert [s["title"] for s in (await client.get("/api/v1/stories")).json()] == ["Фермерское", "Сезон ягод"]

    # правка заменяет слайды целиком; удаление
    edited = (
        await client.put(
            f"{url}/{a['id']}",
            headers=manager,
            json=story(title="Ягоды", slides=[SLIDE | {"cta_label": None, "cta_url": None}]),
        )
    ).json()
    assert edited["title"] == "Ягоды" and len(edited["slides"]) == 1 and edited["slides"][0]["cta_url"] is None
    assert (await client.delete(f"{url}/{b['id']}", headers=manager)).status_code == 204
    assert [s["title"] for s in (await client.get("/api/v1/stories")).json()] == ["Ягоды"]

    # главная страница сайта показывает кружки
    home = (await client.get("/")).text
    assert 'class="stories"' in home and "Ягоды" in home


async def test_story_validation(client, db):
    owner = await staff(client, db, SystemRole.OWNER, "owner-st@test.ru")
    url = "/api/v1/admin/stories"
    bad = [
        story(slides=[]),  # без слайдов
        story(cover_url="javascript:alert(1)"),  # опасная ссылка на картинку
        story(slides=[SLIDE | {"cta_url": "//evil.ru"}]),  # кнопка на чужой сайт без https
        story(slides=[SLIDE | {"cta_url": "javascript:alert(1)"}]),
        story(slides=[SLIDE | {"cta_label": None}]),  # ссылка без текста кнопки
        story(color_hex="red"),
        story(starts_at="2026-10-10T00:00:00Z", ends_at="2026-10-01T00:00:00Z"),
    ]
    for body in bad:
        assert (await client.post(url, headers=owner, json=body)).status_code == 422, body
    ok = story(slides=[SLIDE | {"cta_url": "https://t.me/shop"}])
    assert (await client.post(url, headers=owner, json=ok)).status_code == 201
