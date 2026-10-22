from app.core.errors_ru import translate


def test_translate():
    assert translate("Order not found") == "Заказ не найден"
    assert translate("Not enough stock for Томаты") == "Товар закончился: Томаты"
    assert translate("Maximum 10 addresses") == "Можно сохранить не больше 10 адресов"
    assert translate("Уже по-русски") == "Уже по-русски"
    assert translate("Some internal thing") == "Не удалось выполнить действие — попробуйте ещё раз"


async def test_api_errors_are_russian(client):
    bad = await client.post("/api/v1/auth/register", json={"email": "not-email", "password": "x", "full_name": ""})
    msgs = [d["msg"] for d in bad.json()["detail"]]
    assert bad.status_code == 422
    assert any(m.startswith("Email:") for m in msgs) and any(m.startswith("Имя:") for m in msgs)
    english = ("should", "field", "value", "string", "required", "valid")
    assert not any(w in m.lower() for m in msgs for w in english), msgs

    login = await client.post("/api/v1/auth/login", data={"username": "x@test.ru", "password": "wrong"})
    assert login.json()["detail"] == "Неверный email или пароль"
    assert (await client.get("/api/v1/me/orders")).json()["detail"] == "Войдите в аккаунт"
    assert (await client.get("/api/v1/products/999999")).json()["detail"] == "Товар не найден"

    phone = await client.post("/api/v1/auth/phone/request", json={"phone": "123"})
    assert phone.json()["detail"][0]["msg"].startswith("Телефон:")

    for _ in range(6):
        r = await client.post("/api/v1/auth/login", data={"username": "y@test.ru", "password": "wrong"})
    assert r.status_code == 429 and r.json()["detail"].startswith("Слишком много")
