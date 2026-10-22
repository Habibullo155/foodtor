import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.models import User
from app.services import login_codes
from tests.test_release_flows import register

URL = "/api/v1/auth/email"


@pytest.fixture
def outbox(monkeypatch):
    box = []
    monkeypatch.setattr(login_codes, "SENT_EMAILS", box)
    return box


def _code(msg) -> str:
    return msg["Subject"].split(": ")[1]


async def test_new_email_signup_with_code(client, db, outbox):
    r = await client.post(f"{URL}/request", json={"email": "Anna@Test.ru"})
    assert r.status_code == 200 and r.json()["target"] == "anna@test.ru"
    assert len(outbox) == 1 and outbox[0]["To"] == "anna@test.ru"
    code = _code(outbox[0])
    assert code in outbox[0].get_content() and "5 минут" in outbox[0].get_content()

    v = (await client.post(f"{URL}/verify", json={"email": "anna@test.ru", "code": code})).json()
    assert v["status"] == "need_name"
    done = await client.post(f"{URL}/complete", json={"signup_token": v["signup_token"], "full_name": "Анна"})
    assert done.status_code == 201
    user = await db.scalar(select(User).where(User.email == "anna@test.ru"))
    assert user.full_name == "Анна" and user.email_verified_at is not None


async def test_existing_password_user_can_login_by_email_code(client, db, outbox):
    await register(client, "buyer@test.ru")  # аккаунт с паролем
    await client.post(f"{URL}/request", json={"email": "BUYER@test.ru"})
    v = (await client.post(f"{URL}/verify", json={"email": "buyer@test.ru", "code": _code(outbox[0])})).json()
    assert v["status"] == "ok" and v["access_token"]
    assert (await db.scalar(select(User).where(User.email == "buyer@test.ru"))).email_verified_at is not None
    # тот же код второй раз не работает
    again = await client.post(f"{URL}/verify", json={"email": "buyer@test.ru", "code": _code(outbox[0])})
    assert again.status_code == 400


async def test_email_code_wrong_and_invalid_address(client, outbox):
    assert (await client.post(f"{URL}/request", json={"email": "not-an-email"})).status_code == 422
    await client.post(f"{URL}/request", json={"email": "x@test.ru"})
    wrong = "000000" if _code(outbox[0]) != "000000" else "111111"
    r = await client.post(f"{URL}/verify", json={"email": "x@test.ru", "code": wrong})
    assert r.status_code == 400 and "Осталось попыток: 4" in r.json()["detail"]


async def test_prod_without_smtp_refuses_politely(client, monkeypatch):
    s = get_settings()
    monkeypatch.setattr(s, "app_env", "prod")
    r = await client.post(f"{URL}/request", json={"email": "y@test.ru"})
    assert r.status_code == 503 and "по паролю" in r.json()["detail"]
