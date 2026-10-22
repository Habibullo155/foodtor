import { $, $$, api, cart, esc, icon, logout, requireLogin, rub, toast } from './core.js';
import { cartData } from './cards.js';
import { addressProblem, pickLocation } from './map-picker.js';
import { attachPhoneMask, formatPhone, phoneComplete, phoneDigits } from './phone.js';

let user = await requireLogin();
const main = $('[data-section]');
let poll = null;

const STATUS = { new: 'Принят', picking: 'Собираем', shipped: 'В пути', delivered: 'Доставлен', cancelled: 'Отменён' };
const STEPS = ['new', 'picking', 'shipped', 'delivered'];
const dateFmt = new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
const fmtDate = (s) => dateFmt.format(new Date(s));
const PAY = (o) => (o.payment_status === 'paid' ? (o.payment_method === 'card_online' ? 'Оплачен онлайн' : 'Оплачен')
  : o.payment_method === 'card_online' ? (o.payment_status === 'failed' ? 'Оплата не прошла' : 'Ждём оплату') : 'Оплата при получении');

function renderMe() {
  $('[data-me]').innerHTML = `
    <div class="avatar">${user.avatar_url ? `<img src="${esc(user.avatar_url)}" alt="" width="56" height="56">` : esc((user.full_name || '?').split(' ').map((p) => p[0]).slice(0, 2).join(''))}</div>
    <div><b>${esc(user.full_name)}</b><div class="muted small">${esc(user.email || prettyPhone(user.phone) || '')}</div></div>`;
}

const prettyPhone = (p) => (p && phoneDigits(p).length === 10 ? formatPhone(phoneDigits(p)) : p);

async function ordersView() {
  const orders = await api('/me/orders');
  if (!orders.length) {
    return `<h1>Мои заказы</h1><div class="empty">${icon('cart', 'ic ic--xl')}<h2>Заказов пока нет</h2><a class="btn btn--primary" href="/catalog">В каталог</a></div>`;
  }
  return `<h1>Мои заказы</h1><div class="orders">${orders.map((o) => `
    <a class="order-card panel" href="#order-${o.id}">
      <div class="order-card__head"><b>Заказ ${esc(o.number)}</b><span class="status status--${o.status}">${STATUS[o.status]}</span></div>
      <div class="muted small">${fmtDate(o.created_at)} · ${o.items.reduce((a, i) => a + i.quantity, 0)} шт. · ${PAY(o)}</div>
      <div class="order-card__imgs">${o.items.slice(0, 6).map((i) => (i.image_url ? `<img src="${esc(i.image_url)}" alt="" width="40" height="40" loading="lazy">` : '')).join('')}</div>
      <b class="order-card__total">${rub(o.total)}</b>
    </a>`).join('')}</div>`;
}

function chatHTML(messages, mineIsStaff, closed, placeholder, quick, kind) {
  return `<div class="chat" data-chat="${kind}">
    <div class="chat__list">${messages.length ? messages.map((m) => {
      const mine = m.from_staff === mineIsStaff;
      return `<div class="bubble ${mine ? 'bubble--mine' : ''}"><div class="bubble__author small">${esc(m.author)}</div>${esc(m.text)}<div class="bubble__time small">${fmtDate(m.created_at)}</div></div>`;
    }).join('') : `<p class="muted small">${kind === 'courier' ? 'Напишите курьеру код домофона или как вас найти' : 'Вопрос по заказу? Напишите — ответим здесь'}</p>`}</div>
    ${closed ? '' : `<div class="chips">${quick.map((q) => `<button class="chip" type="button" data-quick="${esc(q)}">${esc(q)}</button>`).join('')}</div>
    <form class="chat__form" data-chat-form="${kind}"><input class="input" name="text" maxlength="1000" placeholder="${placeholder}" autocomplete="off" required>
      <button class="btn btn--primary" type="submit" aria-label="Отправить">${icon('chevron')}</button></form>`}
  </div>`;
}

async function orderView(id) {
  const orders = await api('/me/orders');
  const o = orders.find((x) => x.id === id);
  if (!o) return '<h1>Заказ не найден</h1>';
  const closed = o.status === 'delivered' || o.status === 'cancelled';
  const [comments, courier] = await Promise.all([
    api(`/me/orders/${id}/comments`),
    o.status === 'shipped' ? api(`/me/orders/${id}/courier`).catch(() => null) : null,
  ]);
  const courierChat = courier?.assigned ? await api(`/me/orders/${id}/courier-chat`) : [];
  const step = STEPS.indexOf(o.status);
  return `
    <a class="link" href="#orders">← Все заказы</a>
    <div class="order-head"><h1>Заказ ${esc(o.number)}</h1><span class="status status--${o.status}">${STATUS[o.status]}</span></div>
    <p class="muted">${fmtDate(o.created_at)} · ${PAY(o)}</p>
    ${o.status !== 'cancelled' ? `<ol class="steps">${STEPS.map((s, i) => `<li class="${i <= step ? 'is-done' : ''}">${STATUS[s]}</li>`).join('')}</ol>` : ''}
    ${o.pay_url ? `<button class="btn btn--primary" type="button" data-pay="${o.id}">Оплатить ${rub(o.total)}</button>` : ''}
    ${courier ? `<section class="panel courier">
        ${courier.assigned ? `<div class="courier__head">${icon('truck')}<div><b>Курьер ${esc(courier.courier_name)}</b>
          <div class="muted small">${courier.distance_km != null ? `Примерно ${courier.distance_km} км до вас` : 'Везёт ваш заказ'}</div></div></div>
          <p class="small muted">${courier.phone_opened ? `Курьеру открыт ваш номер: ${esc(courier.phone_reveal_reason || 'он рядом')}` : 'Ваш номер скрыт от курьера — он увидит его, только подъехав к адресу'}</p>
          ${chatHTML(courierChat, false, false, 'Написать курьеру…', ['Я дома, жду', 'Оставьте у двери', 'Код домофона: '], 'courier')}`
        : `<p>${icon('truck')} Заказ передан в доставку, назначаем курьера</p>`}
      </section>` : ''}
    <section class="panel"><h2>Состав</h2>
      ${o.items.map((i) => `<div class="mini-line"><span>${esc(i.name)} <span class="muted">× ${i.quantity}</span></span><b>${rub(i.line_total)}</b></div>`).join('')}
      <dl class="totals"><div><dt>Доставка</dt><dd>${+o.delivery_fee ? rub(o.delivery_fee) : 'бесплатно'}</dd></div><div class="total"><dt>Итого</dt><dd>${rub(o.total)}</dd></div></dl>
      <button class="btn btn--ghost" type="button" data-repeat="${o.id}">${icon('cart')} Повторить заказ</button>
    </section>
    <section class="panel"><h2>Переписка с магазином</h2>${chatHTML(comments, false, closed, 'Сообщение магазину…', ['Позвоните за 10 минут', 'Можно оставить у двери'], 'shop')}</section>`;
}

async function purchasesView() {
  const items = await api('/me/purchases');
  if (!items.length) return `<h1>История покупок</h1><p class="muted">Здесь появятся товары из доставленных заказов.</p>`;
  return `<h1>История покупок</h1><div class="panel lines">${items.map((p) => `
    <div class="line" data-product='${esc(JSON.stringify({ id: p.product_id, name: p.name, price: Number(p.price || 0), image: p.image_url, unit: p.unit, url: `/product/${p.product_id}`, stock: 999 }))}'>
      <span class="line__img">${p.image_url ? `<img src="${esc(p.image_url)}" alt="" width="56" height="56" loading="lazy">` : ''}</span>
      <div class="line__info"><span class="line__name">${esc(p.name)}</span><span class="muted small">Покупали ${p.times_bought} раз · последний ${fmtDate(p.last_bought_at)}</span></div>
      ${p.in_stock && p.price != null ? `<b>${rub(p.price)}</b><div class="qty-slot" data-qty-slot></div>` : '<span class="muted small">Нет в продаже</span>'}
    </div>`).join('')}</div>`;
}

async function addressesView() {
  const list = await api('/me/addresses');
  return `<div class="row row--between"><h1>Мои адреса</h1><button class="btn btn--primary" type="button" data-addr-new>${icon('plus')} Добавить</button></div>
    ${list.length ? list.map((a) => `<div class="panel addr-card">
      <div><b>${esc(a.label)}</b>${a.is_default ? ' <span class="tag tag--fresh">основной</span>' : ''}
        <div>${esc(a.one_line)}</div>${a.courier_note ? `<div class="muted small">Курьеру: ${esc(a.courier_note)}</div>` : ''}
        ${a.in_zone === false ? `<div class="error small">${esc(a.zone_message || 'Сюда мы пока не доставляем')}</div>` : ''}</div>
      <div class="addr-card__actions"><button class="link" type="button" data-addr-edit='${esc(JSON.stringify(a))}'>Изменить</button>
        <button class="link link--danger" type="button" data-addr-del="${a.id}">Удалить</button></div>
    </div>`).join('') : '<p class="muted">Сохраните адрес — при оформлении заказа он подставится сам.</p>'}
    <dialog class="modal" data-addr-dialog><form method="dialog" data-addr-form novalidate>
      <h2 data-addr-title>Новый адрес</h2>
      <div class="chips" data-labels>${['Дом', 'Работа', 'Дача', 'Другое'].map((l) => `<label class="chip"><input type="radio" name="label" value="${l}"><span>${l}</span></label>`).join('')}</div>
      <label class="field"><span>Город, улица, дом</span><input class="input" name="address" maxlength="300" required></label>
      <button class="btn btn--ghost btn--sm" type="button" data-addr-map>${icon('pin')} Выбрать на карте</button>
      <p class="small" data-addr-zone></p>
      <div class="row row--3"><label class="field"><span>Квартира</span><input class="input" name="apartment" maxlength="20"></label>
        <label class="field"><span>Подъезд</span><input class="input" name="entrance" maxlength="10"></label>
        <label class="field"><span>Этаж</span><input class="input" name="floor" maxlength="10"></label></div>
      <div class="row"><label class="field"><span>Домофон</span><input class="input" name="intercom" maxlength="20"></label>
        <label class="field"><span>Комментарий курьеру</span><input class="input" name="courier_note" maxlength="300"></label></div>
      <label class="check"><input type="checkbox" name="is_default"> Основной адрес</label>
      <p class="error" data-addr-error hidden></p>
      <div class="row row--end"><button class="btn btn--ghost" value="cancel" type="submit" formnovalidate>Отмена</button><button class="btn btn--primary" value="save" type="submit">Сохранить</button></div>
    </form></dialog>`;
}

function openAddress(a) {
  const dlg = $('[data-addr-dialog]');
  const f = $('[data-addr-form]');
  let point = a?.lat != null ? { lat: a.lat, lng: a.lng } : null;
  f.reset();
  $('[data-addr-title]').textContent = a ? 'Изменить адрес' : 'Новый адрес';
  ['address', 'apartment', 'entrance', 'floor', 'intercom', 'courier_note'].forEach((k) => { f[k].value = a?.[k] || ''; });
  f.is_default.checked = !!a?.is_default;
  (f.querySelector(`[name=label][value="${a?.label || 'Дом'}"]`) || f.querySelector('[name=label]')).checked = true;
  $('[data-addr-error]').hidden = true;
  $('[data-addr-zone]').textContent = '';
  f.address.oninput = () => { point = null; };
  $('[data-addr-map]').onclick = async () => {
    const p = await pickLocation(point || {});
    dlg.showModal(); // карта закрыла наш диалог — возвращаем
    if (!p) return;
    point = { lat: p.lat, lng: p.lng };
    if (p.address) f.address.value = p.address;
    const z = $('[data-addr-zone]');
    z.className = `small ${p.house ? 'good' : 'warn'}`;
    z.textContent = p.house ? `Точка выбрана: ${p.address}. Укажите квартиру и подъезд.`
      : 'Номер дома не определился — допишите его в адрес';
    (p.house ? f.apartment : f.address).focus();
  };
  f.onsubmit = async (e) => {
    if (e.submitter?.value !== 'save') return;
    e.preventDefault();
    const problem = point ? null : addressProblem(f.address.value);
    const errEl = $('[data-addr-error]');
    if (problem) { errEl.textContent = problem; errEl.hidden = false; return; }
    const body = {
      label: f.querySelector('[name=label]:checked').value, address: f.address.value.trim(),
      apartment: f.apartment.value.trim() || null, entrance: f.entrance.value.trim() || null, floor: f.floor.value.trim() || null,
      intercom: f.intercom.value.trim() || null, courier_note: f.courier_note.value.trim() || null,
      is_default: f.is_default.checked, lat: point?.lat ?? null, lng: point?.lng ?? null,
    };
    try {
      const saved = await api(a ? `/me/addresses/${a.id}` : '/me/addresses', { method: a ? 'PUT' : 'POST', json: body });
      dlg.close();
      toast(saved.in_zone === false ? 'Адрес сохранён, но сюда мы пока не доставляем' : 'Адрес сохранён');
      route();
    } catch (err) { errEl.textContent = err.message; errEl.hidden = false; }
  };
  dlg.showModal();
}

async function profileView() {
  const loyalty = await api('/me/loyalty').catch(() => null);
  return `<h1>Профиль</h1>
    <section class="panel profile">
      <div class="profile__avatar"><div class="avatar avatar--lg">${user.avatar_url ? `<img src="${esc(user.avatar_url)}" alt="" width="96" height="96">` : esc((user.full_name || '?')[0])}</div>
        <label class="btn btn--ghost btn--sm">Загрузить фото<input type="file" accept="image/jpeg,image/png,image/webp" data-avatar hidden></label>
        ${user.avatar_url ? '<button class="link link--danger small" type="button" data-avatar-del>Удалить фото</button>' : ''}
        <p class="muted small">JPG, PNG или WebP до 5 МБ</p></div>
      <form data-profile-form class="profile__form">
        <label class="field"><span>Имя</span><input class="input" name="full_name" value="${esc(user.full_name)}" minlength="2" maxlength="200" required></label>
        <label class="field"><span>Телефон</span><input class="input" name="phone" type="tel" value="${esc(user.phone || '')}"></label>
        <label class="field"><span>${user.email ? 'Email (логин)' : 'Вход'}</span><input class="input" value="${esc(user.email || prettyPhone(user.phone) || '')}" disabled></label>
        <button class="btn btn--primary" type="submit">Сохранить</button>
      </form>
    </section>
    ${loyalty?.current_tier ? `<section class="panel"><h2>Статус «${esc(loyalty.current_tier.name)}»</h2>
      <p>Покупок на ${rub(loyalty.total_spent)}${loyalty.next_tier ? ` · до «${esc(loyalty.next_tier.name)}» осталось ${rub(loyalty.amount_to_next)}` : ''}</p>
      <div class="progress"><div class="progress__bar" data-loyalty-bar="${Math.round(loyalty.progress * 100)}"></div></div></section>` : ''}`;
}

function settingsView() {
  const dark = (document.documentElement.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')) === 'dark';
  return `<h1>Настройки</h1>
    <section class="panel"><h2>Оформление</h2>
      <div class="seg"><label><input type="radio" name="theme" value="light" ${dark ? '' : 'checked'}><span>${icon('sun')} Светлая</span></label>
        <label><input type="radio" name="theme" value="dark" ${dark ? 'checked' : ''}><span>${icon('moon')} Тёмная</span></label></div></section>
    <section class="panel"><h2>Безопасность</h2>
      ${user.email ? `<form class="stack" data-password-change>
        <label class="field"><span>Текущий пароль</span><input class="input" name="current" type="password" autocomplete="current-password" required></label>
        <label class="field"><span>Новый пароль</span><input class="input" name="next" type="password" autocomplete="new-password" minlength="8" required></label>
        <p class="muted small">Минимум 8 символов, буквы и цифры. Остальные устройства выйдут из аккаунта.</p>
        <button class="btn btn--ghost" type="submit">Сменить пароль</button></form>` : '<p class="muted">Вы входите по коду из SMS — пароль не нужен.</p>'}
      <button class="btn btn--ghost" type="button" data-logout-all>Выйти на всех устройствах</button></section>`;
}

async function route() {
  clearInterval(poll);
  const h = location.hash.slice(1) || 'orders';
  const section = h.startsWith('order-') ? 'orders' : h;
  $$('[data-section-link]').forEach((a) => a.classList.toggle('is-active', a.dataset.sectionLink === section));
  main.innerHTML = '<div class="skeleton"></div>';
  try {
    if (h.startsWith('order-')) {
      const id = Number(h.slice(6));
      main.innerHTML = await orderView(id);
      poll = setInterval(async () => { // новые сообщения в чатах
        if (document.activeElement?.closest('[data-chat-form]')) return; // не мешаем печатать
        main.innerHTML = await orderView(id);
      }, 15000);
    } else if (h === 'purchases') main.innerHTML = await purchasesView();
    else if (h === 'addresses') main.innerHTML = await addressesView();
    else if (h === 'profile') {
      main.innerHTML = await profileView();
      attachPhoneMask($('[data-profile-form]').phone);
    }
    else if (h === 'settings') main.innerHTML = settingsView();
    else main.innerHTML = await ordersView();
  } catch (e) {
    main.innerHTML = `<p class="error">${esc(e.message)}</p>`;
  }
  $('[data-loyalty-bar]')?.style.setProperty('--p', `${$('[data-loyalty-bar]').dataset.loyaltyBar}%`);
  window.dispatchEvent(new CustomEvent('cart-rendered'));
}

main.addEventListener('submit', async (e) => {
  const chat = e.target.closest('[data-chat-form]');
  if (chat) {
    e.preventDefault();
    const id = Number(location.hash.slice(7));
    const kind = chat.dataset.chatForm;
    try {
      await api(`/me/orders/${id}/${kind === 'courier' ? 'courier-chat' : 'comments'}`, { method: 'POST', json: { text: chat.text.value.trim() } });
      main.innerHTML = await orderView(id);
    } catch (err) { toast(err.message, 'error'); }
  }
  if (e.target.matches('[data-profile-form]')) {
    e.preventDefault();
    try {
      const ph = e.target.phone.value.trim();
      if (ph && !phoneComplete(ph)) { toast('Введите телефон полностью: +7 (9XX) XXX-XX-XX', 'error'); return; }
      await api('/me/profile', { method: 'PATCH', json: { full_name: e.target.full_name.value.trim(), phone: ph || null } });
      user = await api('/auth/me');
      renderMe();
      toast('Сохранено');
    } catch (err) { toast(err.message, 'error'); }
  }
  if (e.target.matches('[data-password-change]')) {
    e.preventDefault();
    try {
      const r = await api('/auth/change-password', { method: 'POST', json: { current_password: e.target.current.value, new_password: e.target.next.value } });
      (await import('./core.js')).acceptTokens(r);
      e.target.reset();
      toast('Пароль изменён. На других устройствах нужно войти заново.');
    } catch (err) { toast(err.message, 'error'); }
  }
});

main.addEventListener('click', async (e) => {
  const q = e.target.closest('[data-quick]');
  if (q) { const input = q.closest('[data-chat]').querySelector('input[name=text]'); input.value = q.dataset.quick; input.focus(); }
  const pay = e.target.closest('[data-pay]');
  if (pay) { try { location.href = (await api(`/me/orders/${pay.dataset.pay}/pay`, { method: 'POST' })).pay_url; } catch (err) { toast(err.message, 'error'); } }
  const rep = e.target.closest('[data-repeat]');
  if (rep) {
    const o = (await api('/me/orders')).find((x) => x.id === Number(rep.dataset.repeat));
    const { items } = await api(`/products?limit=500`, { auth: false });
    let added = 0;
    o.items.forEach((i) => {
      const p = items.find((x) => x.id === i.product_id);
      if (p?.in_stock) { cart.add(cartData(p), i.quantity); added += i.quantity; }
    });
    toast(added ? `В корзину добавлено ${added} шт.${added < o.items.reduce((a, i) => a + i.quantity, 0) ? ' — часть товаров закончилась' : ''}` : 'Этих товаров сейчас нет');
  }
  if (e.target.closest('[data-addr-new]')) openAddress(null);
  const edit = e.target.closest('[data-addr-edit]');
  if (edit) openAddress(JSON.parse(edit.dataset.addrEdit));
  const del = e.target.closest('[data-addr-del]');
  if (del && confirm('Удалить адрес?')) { await api(`/me/addresses/${del.dataset.addrDel}`, { method: 'DELETE' }); route(); }
  if (e.target.closest('[data-avatar-del]')) { await api('/me/avatar', { method: 'DELETE' }); user = await api('/auth/me'); renderMe(); route(); }
  if (e.target.closest('[data-logout-all]') && confirm('Выйти на всех устройствах? Понадобится войти заново.')) logout(true);
});

main.addEventListener('change', async (e) => {
  if (e.target.matches('[data-avatar]')) {
    const file = e.target.files[0];
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) return toast('Файл больше 5 МБ', 'error');
    const fd = new FormData();
    fd.append('file', file);
    try { await api('/me/avatar', { method: 'POST', form: fd }); user = await api('/auth/me'); renderMe(); route(); toast('Фото обновлено'); } catch (err) { toast(err.message, 'error'); }
  }
  if (e.target.name === 'theme') {
    document.documentElement.dataset.theme = e.target.value;
    try { localStorage.setItem('theme', e.target.value); } catch { /* ok */ }
  }
});

$('[data-logout]').addEventListener('click', () => logout(false));
window.addEventListener('hashchange', route);
renderMe();
route();
