// Возврат со страницы банка: статус уже проверен сервером по API банка (не по параметрам адреса).
import { $, cart, icon } from './core.js';

const q = new URLSearchParams(location.search);
const result = q.get('result');
const order = Number(q.get('order')) || null;
const box = $('[data-payment-return]');
if (result === 'success') {
  cart.clear();
  box.innerHTML = `${icon('check', 'ic ic--xl good')}<h1>Оплата прошла</h1><p class="muted">Спасибо! Мы уже собираем ваш заказ.</p>
    <a class="btn btn--primary" href="/account${order ? `#order-${order}` : ''}">Смотреть заказ</a>`;
} else {
  box.innerHTML = `${icon('x', 'ic ic--xl error')}<h1>Оплата не прошла</h1><p class="muted">Деньги не списаны. Попробуйте ещё раз — заказ сохранён.</p>
    <a class="btn btn--primary" href="/account${order ? `#order-${order}` : '#orders'}">К заказу</a>`;
}
