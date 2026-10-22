import httpx
import pytest
from sqlalchemy import select, update

from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.models import LoginCode, User
from app.services import login_codes as sms
from app.services.login_codes import normalize_phone

URL = "/api/v1/auth/phone"


def test_normalize_phone():
    assert normalize_phone("8 (916) 123-45-67") == "+79161234567"
    assert normalize_phone("+7 916 123 45 67") == "+79161234567"
    assert normalize_phone("9161234567") == "+79161234567"
    assert normalize_phone("+7 495 123-45-67") is None  # городской — SMS не дойдёт
    assert normalize_phone("+1 202 555 0100") is None


async def _request(client, phone="+7 916 123-45-67"):
    r = await client.post(f"{URL}/request", json={"phone": phone})
    assert r.status_code == 200, r.text
    return r.json()


async def test_new_phone_signup_then_login(client, db):
    sent = await _request(client)
    assert sent["phone"] == "+79161234567" and len(sent["dev_code"]) == 6 and sent["resend_in"] == 60

    v = (await client.post(f"{URL}/verify", json={"phone": "89161234567", "code": sent["dev_code"]})).json()
    assert v["status"] == "need_name" and v["signup_token"]
    done = await client.post(f"{URL}/complete", json={"signup_token": v["signup_token"], "full_name": "Ольга"})
    assert done.status_code == 201
    me = (
        await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {done.json()['access_token']}"})
    ).json()
    assert (me["full_name"], me["email"], me["phone"]) == ("Ольга", None, "+79161234567")

    # повторно: тот же номер → сразу вход, без имени
    await db.execute(update(LoginCode).values(created_at=LoginCode.created_at - sms.RESEND_AFTER))
    await db.commit()
    again = await _request(client)
    v2 = (await client.post(f"{URL}/verify", json={"phone": "+79161234567", "code": again["dev_code"]})).json()
    assert v2["status"] == "ok" and v2["access_token"]
    assert len((await db.scalars(select(User).where(User.phone_e164 == "+79161234567"))).all()) == 1

    # код одноразовый
    used = await client.post(f"{URL}/verify", json={"phone": "+79161234567", "code": again["dev_code"]})
    assert used.status_code == 400


async def test_wrong_code_attempts_and_resend_cooldown(client, db):
    sent = await _request(client)
    wrong = "000000" if sent["dev_code"] != "000000" else "111111"
    for left in (4, 3, 2, 1):
        r = await client.post(f"{URL}/verify", json={"phone": sent["phone"], "code": wrong})
        assert r.status_code == 400 and f"Осталось попыток: {left}" in r.json()["detail"]
    await client.post(f"{URL}/verify", json={"phone": sent["phone"], "code": wrong})
    limiter.reset()
    # после 5 ошибок даже верный код не принимается
    locked = await client.post(f"{URL}/verify", json={"phone": sent["phone"], "code": sent["dev_code"]})
    assert locked.status_code == 429

    cooldown = await client.post(f"{URL}/request", json={"phone": sent["phone"]})
    assert cooldown.status_code == 429 and "через" in cooldown.json()["detail"]
    assert int(cooldown.headers["Retry-After"]) <= 60


async def test_hourly_limit_and_bad_numbers(client, db):
    assert (await client.post(f"{URL}/request", json={"phone": "+7 495 111-22-33"})).status_code == 422
    for _ in range(5):
        await _request(client, "+79990000001")
        await db.execute(update(LoginCode).values(created_at=LoginCode.created_at - sms.RESEND_AFTER))
        await db.commit()
        limiter.reset()
    over = await client.post(f"{URL}/request", json={"phone": "+79990000001"})
    assert over.status_code == 429 and "час" in over.json()["detail"]


async def test_expired_signup_token_rejected(client):
    r = await client.post(f"{URL}/complete", json={"signup_token": "garbage", "full_name": "Иван"})
    assert r.status_code == 401


async def test_smsru_provider_sends_and_hides_code(client, db, monkeypatch):
    calls = []

    def handler(request: httpx.Request):
        calls.append(dict(httpx.QueryParams(request.content.decode())))
        return httpx.Response(200, json={"status": "OK", "sms": {"79161234567": {"status": "OK"}}})

    s = get_settings()
    monkeypatch.setattr(s, "sms_provider", "smsru")
    monkeypatch.setattr(s, "smsru_api_id", type(s.jwt_secret)("test-api-id"))
    monkeypatch.setattr(sms, "TEST_TRANSPORT", httpx.MockTransport(handler))
    r = (await client.post(f"{URL}/request", json={"phone": "+79161234567"})).json()
    assert r["dev_code"] is None  # реальная отправка — код только в SMS
    assert calls[0]["to"] == "79161234567" and calls[0]["api_id"] == "test-api-id"
    assert "Код для входа" in calls[0]["msg"]


@pytest.fixture(autouse=True)
def _console_sms(monkeypatch):
    monkeypatch.setattr(get_settings(), "sms_provider", "console")
