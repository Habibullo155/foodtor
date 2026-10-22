import time

from sqlalchemy import event

from app.db.session import engine
from tests import factories as f


async def test_product_list_query_count_is_constant(client, db):
    cat = await f.category(db, "Бакалея")
    for i in range(400):
        await f.product(db, f"Товар {i}", str(50 + i), cat=cat, stock=10)
    await db.commit()

    statements: list[str] = []

    def count(conn, cursor, statement, *a):
        statements.append(statement)

    event.listen(engine.sync_engine, "before_cursor_execute", count)
    try:
        t0 = time.perf_counter()
        r = await client.get("/api/v1/products", params={"limit": 500})
        elapsed = time.perf_counter() - t0
    finally:
        event.remove(engine.sync_engine, "before_cursor_execute", count)

    assert r.status_code == 200 and len(r.json()["items"]) == 400
    print(f"\n400 товаров: {len(statements)} SQL-запросов, {elapsed * 1000:.0f} мс, {len(r.content) // 1024} КБ")
    assert len(statements) <= 10, statements
    assert elapsed < 2.0
