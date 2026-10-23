"""Все ошибки API — по-русски: и наши (HTTPException), и проверки полей (Pydantic).

Тексты в коде остаются короткими английскими «ключами» (так удобнее в логах и тестах API), а пользователю
уходит перевод. Неизвестный текст на латинице заменяется общей фразой — внутренности не показываем.
"""

import re

EXACT = {
    "Address not found": "Адрес не найден",
    "Price list not found": "Прайс-лист не найден",
    "Invalid payment method": "Выберите способ оплаты",
    "B2B account not found": "Оптовый аккаунт не найден",
    "Category not found": "Категория не найдена",
    "Email is already registered": "Этот email уже зарегистрирован",
    "File is not a valid image": "Это не изображение — загрузите JPG, PNG или WebP",
    "Image must be under 5 MB": "Фото должно быть меньше 5 МБ",
    "Insufficient permissions": "Недостаточно прав",
    "Invalid email or password": "Неверный email или пароль",
    "Invalid refresh token": "Сессия истекла — войдите снова",
    "No available products": "Товаров нет в наличии",
    "Order does not need payment": "Этот заказ не нужно оплачивать онлайн",
    "Order is already paid": "Заказ уже оплачен",
    "Order is closed": "Заказ уже закрыт",
    "Order is not paid yet": "Заказ ещё не оплачен",
    "Order not found": "Заказ не найден",
    "Product cannot reference itself": "Товар не может ссылаться сам на себя",
    "Product not found": "Товар не найден",
    "Promo code already exists": "Такой промокод уже есть",
    "Promo code not found": "Промокод не найден",
    "Refresh token reuse detected": "Сессия завершена из соображений безопасности — войдите снова",
    "Review is allowed after the product is delivered": "Отзыв можно оставить после доставки товара",
    "Review not found": "Отзыв не найден",
    "SKU already exists": "Товар с таким артикулом уже есть",
    "Slug already exists": "Такой адрес категории уже занят",
    "Staff member not found": "Сотрудник не найден",
    "Story not found": "История не найдена",
    "Tier not found": "Уровень не найден",
    "Unable to parse file": "Не удалось прочитать файл — проверьте формат",
    "Unknown payment": "Платёж не найден",
    "User inactive": "Аккаунт заблокирован",
    "You cannot demote or deactivate yourself": "Нельзя понизить или отключить самого себя",
    "Cart is empty": "Корзина пуста",
    "Not authenticated": "Войдите в аккаунт",
    "Could not validate credentials": "Сессия истекла — войдите снова",
    "Not Found": "Не найдено",
    "Method Not Allowed": "Действие недоступно",
    "Duplicate product ids": "Товар указан в заказе дважды",
    "Percent discount cannot exceed 100": "Скидка не может быть больше 100%",
    "compare_at_price must be >= retail_price": "«Старая» цена должна быть не меньше текущей",
}

PATTERNS = [
    (re.compile(r"^Not enough stock for (.+)$"), r"Товар закончился: \1"),
    (re.compile(r"^Product \d+ is not available$"), "Один из товаров больше не продаётся — обновите корзину"),
    (re.compile(r"^Unknown product ids: .*$"), "Некоторых товаров уже нет в каталоге — обновите корзину"),
    (re.compile(r"^Maximum (\d+) addresses$"), r"Можно сохранить не больше \1 адресов"),
    (re.compile(r"^File exceeds (\d+) MB$"), r"Файл больше \1 МБ"),
    (re.compile(r"^Transition \w+ → \w+ is not allowed$"), "Такой переход статуса заказа невозможен"),
    (
        re.compile(r"^Payment gateway: .*$"),
        "Банк не ответил — попробуйте оплатить ещё раз или выберите оплату при получении",
    ),
    (re.compile(r"^Amount mismatch.*$"), "Сумма оплаты не совпала с заказом — мы проверим и свяжемся с вами"),
]

GENERIC = "Не удалось выполнить действие — попробуйте ещё раз"
_CYRILLIC = re.compile("[а-яА-ЯёЁ]")


def translate(message: str) -> str:
    if not message:
        return message
    if message in EXACT:
        return EXACT[message]
    for rx, repl in PATTERNS:  # до проверки на кириллицу: в шаблон может попасть русское название товара
        if rx.match(message):
            return rx.sub(repl, message)
    return message if _CYRILLIC.search(message) else GENERIC


FIELDS = {
    "phone": "Телефон",
    "email": "Email",
    "username": "Email",
    "password": "Пароль",
    "new_password": "Новый пароль",
    "current_password": "Текущий пароль",
    "full_name": "Имя",
    "name": "Имя",
    "address": "Адрес",
    "code": "Код",
    "apartment": "Квартира",
    "entrance": "Подъезд",
    "floor": "Этаж",
    "intercom": "Домофон",
    "courier_note": "Комментарий курьеру",
    "note": "Комментарий",
    "text": "Сообщение",
    "label": "Название",
    "title": "Название",
    "promo_code": "Промокод",
    "quantity": "Количество",
    "items": "Товары",
    "rating": "Оценка",
    "reason": "Причина",
    "radius_km": "Радиус",
    "sku": "Артикул",
    "retail_price": "Цена",
    "cost_price": "Себестоимость",
    "stock": "Остаток",
    "image_url": "Фото",
    "cover_url": "Обложка",
    "headline": "Заголовок",
    "cta_url": "Ссылка",
    "cta_label": "Текст кнопки",
    "slides": "Слайды",
    "color_hex": "Цвет",
    "min_total_spent": "Сумма покупок",
    "discount_value": "Скидка",
    "lat": "Точка на карте",
    "lng": "Точка на карте",
    "signup_token": "Подтверждение",
    "file": "Файл",
}


def field_error(err: dict) -> str:
    """Одна ошибка Pydantic → «Телефон: неверный формат»."""
    loc = [p for p in err.get("loc", ()) if isinstance(p, str) and p not in ("body", "query", "path", "form")]
    label = FIELDS.get(loc[-1], "") if loc else ""
    t = err.get("type", "")
    ctx = err.get("ctx") or {}
    msg = str(err.get("msg", ""))
    if t == "value_error" and _CYRILLIC.search(msg):
        text = msg.removeprefix("Value error, ")  # наши проверки уже пишут по-русски
        return text if not label or text.startswith(label) else text
    text = {
        "missing": "обязательное поле",
        "string_too_short": f"слишком коротко (минимум {ctx.get('min_length')} симв.)",
        "string_too_long": f"слишком длинно (максимум {ctx.get('max_length')} симв.)",
        "string_pattern_mismatch": "неверный формат",
        "value_error": "неверное значение",
        "too_short": "нужно указать хотя бы одно значение"
        if ctx.get("min_length") == 1
        else f"минимум {ctx.get('min_length')}",
        "too_long": f"не больше {ctx.get('max_length')}",
        "greater_than": f"должно быть больше {ctx.get('gt')}",
        "greater_than_equal": f"должно быть не меньше {ctx.get('ge')}",
        "less_than": f"должно быть меньше {ctx.get('lt')}",
        "less_than_equal": f"должно быть не больше {ctx.get('le')}",
        "int_parsing": "нужно целое число",
        "int_type": "нужно целое число",
        "float_parsing": "нужно число",
        "decimal_parsing": "нужно число",
        "float_type": "нужно число",
        "bool_parsing": "нужно да/нет",
        "datetime_parsing": "неверная дата",
        "datetime_from_date_parsing": "неверная дата",
        "enum": "недопустимое значение",
        "literal_error": "недопустимое значение",
        "json_invalid": "неверные данные",
        "model_attributes_type": "неверные данные",
        "dict_type": "неверные данные",
        "list_type": "нужен список",
        "string_type": "нужен текст",
    }.get(t, "неверное значение")
    if t == "value_error" and "email" in msg.lower():
        text = "неверный email"
    return f"{label}: {text}" if label else text[:1].upper() + text[1:]
