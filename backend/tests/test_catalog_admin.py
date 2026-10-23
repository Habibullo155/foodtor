import io

import pandas as pd
from sqlalchemy import select

from app.models import Category, Product, SystemRole
from tests import factories as f
from tests.test_release_flows import staff


async def test_hidden_category_hides_its_products_everywhere(client, db):
    fruit = await f.category(db, "Фрукты")
    grocery = await f.category(db, "Бакалея")
    grocery.is_visible, grocery.slug = False, "bakaleya"
    await f.product(db, "Яблоки", cat=fruit)
    rice = await f.product(db, "Рис", cat=grocery)
    await db.commit()

    cats = (await client.get("/api/v1/categories")).json()
    assert [c["name"] for c in cats] == ["Фрукты"]
    names = [p["name"] for p in (await client.get("/api/v1/products")).json()["items"]]
    assert names == ["Яблоки"]
    assert (await client.get(f"/api/v1/products/{rice.id}")).status_code == 404
    assert (await client.get(f"/catalog/{grocery.slug}")).status_code == 404
    assert "Поиск «Рис»: 0 товаров" in (await client.get("/catalog", params={"q": "Рис"})).text

    owner = await staff(client, db, SystemRole.OWNER, "owner-cat@test.ru")
    admin = (await client.get("/api/v1/admin/categories", headers=owner)).json()
    hidden = next(c for c in admin if c["name"] == "Бакалея")
    assert (hidden["is_visible"], hidden["products_count"]) == (False, 1)

    body = {"name": "Бакалея", "slug": grocery.slug, "is_visible": True}
    assert (await client.patch(f"/api/v1/admin/categories/{grocery.id}", json=body, headers=owner)).status_code == 200
    assert (await client.get(f"/api/v1/products/{rice.id}")).status_code == 200


async def test_bulk_hide_show_move_delete(client, db):
    veg = await f.category(db, "Овощи")
    a, b, c = [await f.product(db, n, cat=veg) for n in ("Лук", "Чеснок", "Укроп")]
    await db.commit()
    ids = [a.id, b.id, c.id]
    owner = await staff(client, db, SystemRole.OWNER, "owner-bulk@test.ru")
    url = "/api/v1/admin/products/bulk"

    r = await client.post(url, json={"ids": [a.id, b.id], "action": "hide"}, headers=owner)
    assert r.json() == {"affected": 2}
    await db.refresh(a)
    assert a.is_active is False
    await client.post(url, json={"ids": [a.id], "action": "show"}, headers=owner)
    await client.post(url, json={"ids": [c.id], "action": "move", "category_id": None}, headers=owner)
    assert (await client.post(url, json={"ids": [b.id, c.id], "action": "delete"}, headers=owner)).json()["affected"] == 2

    db.expire_all()
    left = (await db.scalars(select(Product).where(Product.id.in_(ids)))).unique().all()
    assert [(p.name, p.is_active) for p in left] == [("Лук", True)]

    courier = await staff(client, db, SystemRole.COURIER, "courier-bulk@test.ru")
    assert (await client.post(url, json={"ids": ids[:1], "action": "delete"}, headers=courier)).status_code == 403


async def test_brands_list_rename_delete(client, db):
    p = await f.product(db, "Мёд")
    p.brand = "Пасека"
    await db.commit()
    owner = await staff(client, db, SystemRole.OWNER, "owner-brand@test.ru")

    listed = (await client.get("/api/v1/admin/brands", headers=owner)).json()
    assert listed == [{"id": None, "name": "Пасека", "logo_url": None, "products_count": 1}]
    created = (await client.post("/api/v1/admin/brands", json={"name": "Пасека"}, headers=owner)).json()
    assert created["products_count"] == 1
    assert (await client.post("/api/v1/admin/brands", json={"name": "пасека"}, headers=owner)).status_code == 409

    r = await client.put(f"/api/v1/admin/brands/{created['id']}", json={"name": "Пасека Алтая"}, headers=owner)
    assert r.json()["products_count"] == 1
    await db.refresh(p)
    assert p.brand == "Пасека Алтая"

    assert (await client.delete(f"/api/v1/admin/brands/{created['id']}", headers=owner)).status_code == 204
    await db.refresh(p)
    assert p.brand is None
    assert (await client.get("/api/v1/admin/brands", headers=owner)).json() == []


async def test_excel_categories_sheet_round_trip(client, db):
    fruit = await f.category(db, "Фрукты")
    await f.product(db, "Груши", cat=fruit)
    await db.commit()
    owner = await staff(client, db, SystemRole.OWNER, "owner-sheet@test.ru")

    exported = await client.get("/api/v1/admin/products/export", headers=owner)
    sheets = pd.read_excel(io.BytesIO(exported.content), dtype=str, sheet_name=None)
    assert list(sheets) == ["Товары", "Категории"]
    cats = sheets["Категории"]
    assert cats.loc[0, "Показывать на сайте"] == "да"

    cats.loc[0, "Показывать на сайте"] = "нет"
    cats = pd.concat([cats, pd.DataFrame([{"Категория": "Бытовая химия", "Показывать на сайте": "нет"}])])
    buf = io.BytesIO()
    with pd.ExcelWriter(buf) as w:
        sheets["Товары"].to_excel(w, index=False, sheet_name="Товары")
        cats.to_excel(w, index=False, sheet_name="Категории")
    r = await client.post(
        "/api/v1/admin/products/import",
        headers=owner,
        files={"file": ("all.xlsx", buf.getvalue(), "application/octet-stream")},
    )
    assert r.json()["categories_updated"] == 2 and r.json()["failed"] == 0

    db.expire_all()
    visible = dict((await db.execute(select(Category.name, Category.is_visible))).tuples().all())
    assert visible == {"Фрукты": False, "Бытовая химия": False}
