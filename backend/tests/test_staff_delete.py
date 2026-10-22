from app.models import SystemRole
from tests.test_release_flows import checkout_body, shop, staff


async def test_delete_staff_rules(client, db):
    owner = await staff(client, db, SystemRole.OWNER, "owner-del@test.ru")
    manager = await staff(client, db, SystemRole.MANAGER, "manager-del@test.ru")
    picker = await staff(client, db, SystemRole.PICKER, "picker-del@test.ru")
    ids = {s["email"]: s["id"] for s in (await client.get("/api/v1/admin/staff", headers=owner)).json()}

    # менеджер без staff:manage — нельзя
    assert (await client.delete(f"/api/v1/admin/staff/{ids['picker-del@test.ru']}", headers=manager)).status_code == 403
    # себя — нельзя, последнего владельца — тоже
    assert (await client.delete(f"/api/v1/admin/staff/{ids['owner-del@test.ru']}", headers=owner)).status_code == 409

    r = await client.delete(f"/api/v1/admin/staff/{ids['picker-del@test.ru']}", headers=owner)
    assert r.status_code == 200 and r.json() == {"deleted": True}
    assert "picker-del@test.ru" not in {
        s["email"] for s in (await client.get("/api/v1/admin/staff", headers=owner)).json()
    }
    assert (await client.get("/api/v1/staff/picking", headers=picker)).status_code == 401  # токен больше не действует
    assert (await client.delete(f"/api/v1/admin/staff/{ids['picker-del@test.ru']}", headers=owner)).status_code == 404


async def test_delete_staff_with_own_orders_keeps_customer_account(client, db):
    tomato, _ = await shop(db)
    owner = await staff(client, db, SystemRole.OWNER, "owner-del2@test.ru")
    second_owner = await staff(client, db, SystemRole.OWNER, "owner-del3@test.ru")
    manager = await staff(client, db, SystemRole.MANAGER, "manager-del2@test.ru")
    await client.post("/api/v1/me/orders", headers=manager, json=checkout_body((tomato, 1)))  # сотрудник покупал сам
    ids = {s["email"]: s["id"] for s in (await client.get("/api/v1/admin/staff", headers=owner)).json()}

    r = await client.delete(f"/api/v1/admin/staff/{ids['manager-del2@test.ru']}", headers=owner)
    assert r.json() == {"deleted": False}
    assert (await client.get("/api/v1/admin/orders", headers=manager)).status_code == 401
    # второй владелец есть → первого удалить можно
    assert (await client.delete(f"/api/v1/admin/staff/{ids['owner-del3@test.ru']}", headers=owner)).json() == {
        "deleted": True
    }
    assert second_owner  # (заголовки удалённого больше не нужны)
