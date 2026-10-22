from app.core.rate_limit import limiter
from app.models import SystemRole
from tests.test_release_flows import staff

PWD = "Ogurec-2026-zelen"


async def _register(client, email="buyer@test.ru", password=PWD):
    r = await client.post(
        "/api/v1/auth/register", json={"email": email, "password": password, "full_name": "Покупатель"}
    )
    return r


async def _login(client, email, password):
    return await client.post("/api/v1/auth/login", data={"username": email, "password": password})


async def test_weak_passwords_rejected(client, db):
    for bad in ("qwerty123", "12345678", "onlyletters", "aaaa1111", "buyer2026x"):
        r = await _register(client, password=bad)
        assert r.status_code == 422, bad
    assert (await _register(client)).status_code == 201


async def test_account_locks_after_five_failures_without_revealing_existence(client, db):
    await _register(client)
    for _ in range(5):
        assert (await _login(client, "buyer@test.ru", "wrong-pass-1")).status_code == 401
    limiter.reset()  # убираем лимит по IP — проверяем именно блокировку аккаунта
    locked = await _login(client, "buyer@test.ru", PWD)  # даже верный пароль не пускает
    assert locked.status_code == 429 and "Слишком много" in locked.json()["detail"]
    assert int(locked.headers["Retry-After"]) > 0

    # несуществующий email блокируется так же — по ответу нельзя понять, есть ли аккаунт
    limiter.reset()
    for _ in range(5):
        await _login(client, "ghost@test.ru", "wrong-pass-1")
    limiter.reset()
    assert (await _login(client, "ghost@test.ru", "wrong-pass-1")).status_code == 429


async def test_successful_login_resets_counter(client, db):
    await _register(client)
    for _ in range(4):
        await _login(client, "buyer@test.ru", "wrong-pass-1")
    limiter.reset()
    assert (await _login(client, "buyer@test.ru", PWD)).status_code == 200
    assert (await _login(client, "buyer@test.ru", "wrong-pass-1")).status_code == 401
    assert (await _login(client, "buyer@test.ru", PWD)).status_code == 200  # счётчик начался заново


async def test_change_password_kills_old_sessions(client, db):
    old = (await _register(client)).json()
    h_old = {"Authorization": f"Bearer {old['access_token']}"}

    wrong = await client.post(
        "/api/v1/auth/change-password",
        headers=h_old,
        json={"current_password": "nope", "new_password": "Pomidor-77-krasny"},
    )
    assert wrong.status_code == 400
    weak = await client.post(
        "/api/v1/auth/change-password", headers=h_old, json={"current_password": PWD, "new_password": "password123"}
    )
    assert weak.status_code == 422

    new = await client.post(
        "/api/v1/auth/change-password",
        headers=h_old,
        json={"current_password": PWD, "new_password": "Pomidor-77-krasny"},
    )
    assert new.status_code == 200
    h_new = {"Authorization": f"Bearer {new.json()['access_token']}"}
    assert (await client.get("/api/v1/auth/me", headers=h_old)).status_code == 401
    assert (await client.get("/api/v1/auth/me", headers=h_new)).status_code == 200
    stale = await client.post("/api/v1/auth/refresh", json={"refresh_token": old["refresh_token"]})
    assert stale.status_code == 401
    limiter.reset()
    assert (await _login(client, "buyer@test.ru", PWD)).status_code == 401
    assert (await _login(client, "buyer@test.ru", "Pomidor-77-krasny")).status_code == 200


async def test_logout_everywhere(client, db):
    a = (await _register(client)).json()
    b = (await _login(client, "buyer@test.ru", PWD)).json()  # второе устройство
    h = {"Authorization": f"Bearer {a['access_token']}"}
    assert (await client.post("/api/v1/auth/logout-all", headers=h)).status_code == 204
    assert (await client.get("/api/v1/auth/me", headers=h)).status_code == 401
    assert (await client.post("/api/v1/auth/refresh", json={"refresh_token": b["refresh_token"]})).status_code == 401


async def test_loyalty_tiers_edit_and_conflicts(client, db):
    owner = await staff(client, db, SystemRole.OWNER, "owner-tiers@test.ru")
    url = "/api/v1/admin/loyalty-tiers"
    base = {"name": "Silver", "min_total_spent": "10000", "discount_value": "3"}
    tid = (await client.post(url, headers=owner, json=base)).json()["id"]
    await client.post(url, headers=owner, json={"name": "Gold", "min_total_spent": "30000", "discount_value": "5"})

    dup = await client.post(url, headers=owner, json=base | {"name": "silver", "min_total_spent": "5000"})
    assert dup.status_code == 409 and "названием" in dup.json()["detail"]
    same_threshold = await client.put(f"{url}/{tid}", headers=owner, json=base | {"min_total_spent": "30000"})
    assert same_threshold.status_code == 409
    too_much = await client.put(f"{url}/{tid}", headers=owner, json=base | {"discount_value": "150"})
    assert too_much.status_code == 422

    ok = await client.put(f"{url}/{tid}", headers=owner, json=base | {"name": "Серебро", "discount_value": "4"})
    assert ok.status_code == 200
    rows = {t["name"]: t for t in (await client.get(url, headers=owner)).json()}
    assert float(rows["Серебро"]["discount_value"]) == 4
    assert (await client.delete(f"{url}/{tid}", headers=owner)).status_code == 204
    assert "Серебро" not in {t["name"] for t in (await client.get(url, headers=owner)).json()}


async def test_refresh_reuse_within_grace_keeps_session(client, db):
    """Перезагрузка страницы оборвала ответ на ротацию → клиент шлёт старый токен ещё раз: это не кража."""
    first = (await _register(client)).json()
    r1 = await client.post("/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert r1.status_code == 200
    again = await client.post("/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert again.status_code == 200  # в пределах 30 с — сессия продолжается
    newest = again.json()
    assert (
        await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {newest['access_token']}"})
    ).status_code == 200
    # токен из «оборванного» ответа тоже рабочий — не выкидываем вторую вкладку
    assert (
        await client.post("/api/v1/auth/refresh", json={"refresh_token": r1.json()["refresh_token"]})
    ).status_code == 200


async def test_refresh_reuse_after_logout_or_late_is_theft(client, db):
    from datetime import timedelta

    from sqlalchemy import update

    from app.models import RefreshToken

    first = (await _register(client)).json()
    r1 = (await client.post("/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]})).json()
    # прошло больше 30 с — старый токен снова пришёл: это кража, отзываем все сессии
    await db.execute(update(RefreshToken).values(rotated_at=RefreshToken.rotated_at - timedelta(minutes=5)))
    await db.commit()
    stolen = await client.post("/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert stolen.status_code == 401
    assert (await client.post("/api/v1/auth/refresh", json={"refresh_token": r1["refresh_token"]})).status_code == 401

    # отозванный выходом токен не «воскрешается» даже сразу
    fresh = (await client.post("/api/v1/auth/login", data={"username": "buyer@test.ru", "password": PWD})).json()
    await client.post("/api/v1/auth/logout", json={"refresh_token": fresh["refresh_token"]})
    assert (
        await client.post("/api/v1/auth/refresh", json={"refresh_token": fresh["refresh_token"]})
    ).status_code == 401
