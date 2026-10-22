from app.models import Review, ReviewStatus, SystemRole
from tests import factories as f
from tests.test_release_flows import shop, staff


async def test_bulk_moderation(client, db):
    tomato, dill = await shop(db)
    buyers = [await f.customer(db, f"b{i}@test.ru") for i in range(5)]  # один отзыв на товар от человека
    reviews = [
        Review(product_id=tomato.id, user_id=b.id, rating=r, text=f"Оценка {r}")
        for b, r in zip(buyers, (5, 5, 4, 2, 1), strict=True)
    ]
    db.add_all(reviews)
    await db.commit()
    owner = await staff(client, db, SystemRole.OWNER, "owner-rev@test.ru")
    picker = await staff(client, db, SystemRole.PICKER, "picker-rev@test.ru")
    high = [r.id for r in reviews if r.rating >= 4]
    low = [r.id for r in reviews if r.rating <= 2]

    assert (
        await client.post("/api/v1/admin/reviews/moderate-bulk", headers=picker, json={"ids": high, "approve": True})
    ).status_code == 403
    ok = await client.post("/api/v1/admin/reviews/moderate-bulk", headers=owner, json={"ids": high, "approve": True})
    assert ok.json() == {"updated": 3}
    rej = await client.post(
        "/api/v1/admin/reviews/moderate-bulk", headers=owner, json={"ids": low, "approve": False, "reason": "Спам"}
    )
    assert rej.json() == {"updated": 2}
    assert (
        await client.post("/api/v1/admin/reviews/moderate-bulk", headers=owner, json={"ids": [], "approve": True})
    ).status_code == 422

    rows = {r["id"]: r["status"] for r in (await client.get("/api/v1/admin/reviews", headers=owner)).json()}
    assert all(rows[i] == ReviewStatus.APPROVED.value for i in high)
    assert all(rows[i] == ReviewStatus.REJECTED.value for i in low)
    # на витрине — только одобренные: средняя 14/3
    card = (await client.get(f"/api/v1/products/{tomato.id}")).json()
    assert round(card["rating"], 1) == 4.7 and card["reviews_count"] == 3
