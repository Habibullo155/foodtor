import { $, $$, api, cart, deliveryFee, DELIVERY, esc, FREE_FROM, icon, me, plural, rub } from './core.js';
import { cardHTML } from './cards.js';

const page = $('[data-cart-page]');
const PREF = 'cart_prefs';
const prefs = (() => { try { return JSON.parse(sessionStorage.getItem(PREF)) || {}; } catch { return {}; } })();
const savePrefs = () => { try { sessionStorage.setItem(PREF, JSON.stringify(prefs)); } catch { /* ok */ } };
let user = null;
let quote = null;
let quoteSeq = 0;

function lineHTML(l) {
  return `<div class="line" data-product='${esc(JSON.stringify(l))}'>
    <a class="line__img" href="${esc(l.url)}">${l.image ? `<img src="${esc(l.image)}" alt="" width="72" height="72">` : ''}</a>
    <div class="line__info"><a href="${esc(l.url)}" class="line__name">${esc(l.name)}</a>
      <span class="muted small">${l.unit ? esc(l.unit) + ' · ' : ''}${rub(l.price)} за шт.</span></div>
    <div class="qty-slot" data-qty-slot></div>
    <b class="line__sum">${rub(l.price * l.qty)}</b>
    <button class="icon-btn" type="button" data-remove aria-label="Удалить">${icon('trash')}</button>
  </div>`;
}

async function loadQuote() {
  const lines = cart.lines();
  if (!user || !lines.length) { quote = null; return; }
  const seq = ++quoteSeq;
  try {
    const q = await api('/me/orders/quote', { method: 'POST', json: {
      items: lines.map((l) => ({ product_id: l.id, quantity: l.qty })),
      delivery: prefs.delivery || 'courier', promo_code: prefs.promo || null,
    } });
    if (seq === quoteSeq) quote = q;
  } catch { if (seq === quoteSeq) quote = null; }
  if (quote) syncPrices(quote);
}

// В корзине могла остаться цена со времени добавления (например, розничная до подключения опта)
function syncPrices(q) {
  const lines = cart.all();
  const stale = q.lines.filter((l) => lines[l.product_id] && lines[l.product_id].price !== Number(l.unit_price));
  stale.forEach((l) => cart.set({ ...lines[l.product_id], price: Number(l.unit_price) }, lines[l.product_id].qty));
}

function renderTotals() {
  const lines = cart.lines();
  const goods = lines.reduce((a, l) => a + l.qty * l.price, 0);
  const kind = prefs.delivery || 'courier';
  const t = quote
    ? { subtotal: +quote.subtotal, loyalty: +quote.loyalty_discount, promo: +quote.promo_discount, fee: +quote.delivery_fee, total: +quote.total }
    : { subtotal: goods, loyalty: 0, promo: 0, fee: deliveryFee(kind, goods), total: goods + deliveryFee(kind, goods) };
  const row = (k, v, cls = '') => `<div class="${cls}"><dt>${k}</dt><dd>${v}</dd></div>`;
  const savings = quote?.wholesale
    ? quote.lines.reduce((a, l) => a + (Number(l.retail_unit_price) - Number(l.unit_price)) * l.quantity, 0)
    : 0;
  $('[data-totals]', page).innerHTML =
    row(`Товары (${cart.count()} шт.)`, rub(t.subtotal)) +
    (savings ? row('Выгода по оптовым ценам', '−' + rub(savings), 'good') : '') +
    (t.loyalty ? row(`Скидка ${esc(quote.tier_name || 'по статусу')}`, '−' + rub(t.loyalty), 'good') : '') +
    (t.promo ? row('Промокод', '−' + rub(t.promo), 'good') : '') +
    row(DELIVERY[kind].label, t.fee ? rub(t.fee) : 'бесплатно', t.fee ? '' : 'good') +
    row('Итого', rub(t.total), 'total');

  const bar = $('[data-free-progress]', page);
  bar.hidden = kind !== 'courier';
  const left = Math.max(0, FREE_FROM - goods);
  $('.progress__bar', bar).style.setProperty('--p', `${Math.min(100, (goods / FREE_FROM) * 100)}%`);
  $('[data-free-text]', bar).textContent = left ? `Ещё ${rub(left)} — и курьерская доставка бесплатно` : 'Курьерская доставка — бесплатно';

  const min = quote?.wholesale ? Number(quote.wholesale_min_order) : 0;
  const short = Math.max(0, min - t.subtotal);
  const minMsg = $('[data-min-order]', page);
  minMsg.hidden = !short;
  minMsg.textContent = short ? `Минимальный заказ для оптовых клиентов — ${rub(min)}. Добавьте ещё на ${rub(short)}` : '';
  const btn = $('[data-checkout-btn]', page);
  btn.classList.toggle('is-disabled', short > 0);
  btn.setAttribute('aria-disabled', short > 0 ? 'true' : 'false');

  const msg = $('[data-promo-msg]', page);
  msg.className = 'small';
  if (!user && prefs.promo) { msg.textContent = 'Промокод применится после входа'; }
  else if (quote?.promo_error) { msg.textContent = quote.promo_error; msg.classList.add('error'); }
  else if (quote && t.promo) { msg.textContent = `Промокод «${prefs.promo}» применён`; msg.classList.add('good'); }
  else msg.textContent = '';
}

async function render() {
  const lines = cart.lines();
  const box = $('[data-cart-lines]', page);
  const summary = $('[data-cart-summary]', page);
  if (!lines.length) {
    box.innerHTML = `<div class="empty">${icon('cart', 'ic ic--xl')}<h2>В корзине пока пусто</h2>
      <p class="muted">Загляните в каталог — там много свежего</p><a class="btn btn--primary" href="/catalog">В каталог</a></div>`;
    summary.hidden = true;
    $('[data-recs]').hidden = true;
    return;
  }
  box.innerHTML = `<div class="panel lines">${lines.map(lineHTML).join('')}
    <div class="lines__foot"><span class="muted">${cart.count()} ${plural(cart.count(), 'товар', 'товара', 'товаров')}</span>
    <button class="link link--danger" type="button" data-clear>Очистить корзину</button></div></div>`;
  summary.hidden = false;
  window.dispatchEvent(new CustomEvent('cart-rendered'));
  renderTotals();
  await loadQuote();
  renderTotals();
}

async function loadRecs() {
  const ids = cart.lines().map((l) => l.id);
  if (!ids.length) return;
  try {
    const q = ids.slice(0, 50).map((i) => `ids=${i}`).join('&');
    const r = await api(`/products/recommendations?${q}&limit=8`, { auth: false });
    const items = r.products.filter((p) => !cart.qty(p.id));
    $('[data-recs]').hidden = !items.length;
    $('[data-recs-list]').innerHTML = items.map(cardHTML).join('');
    window.dispatchEvent(new CustomEvent('cart-rendered')); // кнопки «В корзину» на новых карточках
  } catch { /* рекомендации необязательны */ }
}

page.addEventListener('click', (e) => {
  if (e.target.closest('[data-checkout-btn].is-disabled')) e.preventDefault();
  if (e.target.closest('[data-remove]')) {
    const l = JSON.parse(e.target.closest('[data-product]').dataset.product);
    cart.set(l, 0);
  }
  if (e.target.closest('[data-clear]') && confirm('Убрать все товары из корзины?')) cart.clear();
});

$$('[data-delivery] input').forEach((r) => {
  r.checked = r.value === (prefs.delivery || 'courier');
  r.addEventListener('change', () => { prefs.delivery = r.value; savePrefs(); render(); });
});

$('[data-promo]').addEventListener('submit', (e) => {
  e.preventDefault();
  prefs.promo = e.target.code.value.trim().toUpperCase() || null;
  savePrefs();
  render();
});
if (prefs.promo) $('[data-promo]').code.value = prefs.promo;

let lastIds = '';
window.addEventListener('cart', () => {
  render();
  const ids = cart.lines().map((l) => l.id).sort().join(',');
  if (ids !== lastIds) { lastIds = ids; loadRecs(); }
});

user = await me();
lastIds = cart.lines().map((l) => l.id).sort().join(',');
await render();
loadRecs();
