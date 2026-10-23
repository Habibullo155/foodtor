const rubFmt = new Intl.NumberFormat('ru-RU', { style: 'currency', currency: 'RUB', maximumFractionDigits: 2, minimumFractionDigits: 0 });
export const rub = (v) => rubFmt.format(Number(v) || 0);

export function plural(n, one, few, many) {
  const n10 = n % 10, n100 = n % 100;
  if (n10 === 1 && n100 !== 11) return one;
  if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return few;
  return many;
}

/** Экранирование для вставки в HTML — всё пользовательское проходит через esc(). */
export function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

export function debounce(fn, ms) {
  let t;
  return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
}

export const ICONS = document.querySelector('link[rel=stylesheet]')?.href.replace(/css\/shop\.css.*$/, 'icons.svg') || '/static/icons.svg';
export const icon = (name, cls = 'ic') => `<svg class="${cls}" aria-hidden="true"><use href="${ICONS}#i-${name}"/></svg>`;

let toastTimer;
export function toast(text, kind = '') {
  const el = $('[data-toast]');
  if (!el) return;
  el.textContent = text;
  el.className = `toast ${kind ? 'toast--' + kind : ''}`;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 3500);
}

// Refresh-токен — в HttpOnly-cookie (JS его не видит). Access-токен (живёт 15 минут) держим в sessionStorage
// вкладки: переход между страницами не дёргает /auth/refresh, а значит, нечему «оборваться» при перезагрузке.
const ACCESS_KEY = 'access_v1';
let access = null;
let refreshing = null;

function tokenExp(t) {
  try { return JSON.parse(atob(t.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).exp * 1000; } catch { return 0; }
}
function storeAccess(t) {
  access = t;
  try { t ? sessionStorage.setItem(ACCESS_KEY, t) : sessionStorage.removeItem(ACCESS_KEY); } catch { /* ok */ }
}
(() => {
  try {
    const t = sessionStorage.getItem(ACCESS_KEY);
    if (t && tokenExp(t) - Date.now() > 60_000) access = t; // ещё минута жизни — пользуемся
  } catch { /* ok */ }
})();
const SESSION_FLAG = 'has_session'; // не секрет: лишь подсказка «стоит попробовать обновить сессию»

function hasSessionHint() { try { return localStorage.getItem(SESSION_FLAG) === '1'; } catch { return false; } }
function setSessionHint(on) { try { on ? localStorage.setItem(SESSION_FLAG, '1') : localStorage.removeItem(SESSION_FLAG); } catch { /* ok */ } }

export class ApiError extends Error {
  constructor(message, status) { super(message); this.status = status; }
}

const EN_RU = {
  'Invalid email or password': 'Неверный email или пароль',
  'Email is already registered': 'Этот email уже зарегистрирован',
  'Not authenticated': 'Войдите в аккаунт',
  'Order is closed': 'Заказ уже закрыт',
};

async function errorFrom(res) {
  let msg = res.status === 429 ? 'Слишком много попыток, подождите немного' : 'Что-то пошло не так, попробуйте ещё раз';
  try {
    const j = await res.json();
    if (typeof j.detail === 'string') msg = j.detail;
    else if (Array.isArray(j.detail) && j.detail[0]?.msg) msg = String(j.detail[0].msg).replace(/^Value error, /, '');
  } catch { /* не JSON */ }
  if (msg.startsWith('Not enough stock for ')) msg = 'Товар закончился: ' + msg.slice(21);
  return new ApiError(EN_RU[msg] || msg, res.status);
}

/** Обновить access по cookie. true — сессия есть. Параллельные вызовы ждут один запрос. */
export function refreshSession() {
  if (!refreshing) {
    refreshing = fetch('/api/v1/auth/refresh', { method: 'POST', headers: { 'X-Session': 'cookie' }, credentials: 'same-origin' })
      .then(async (r) => {
        if (!r.ok) {
          // 401 — сессии правда нет; прочие ошибки (сеть, 429, 5xx) — не выкидываем, попробуем позже
          if (r.status === 401) { storeAccess(null); setSessionHint(false); }
          return false;
        }
        storeAccess((await r.json()).access_token);
        setSessionHint(true);
        return true;
      })
      .catch(() => false)
      .finally(() => { setTimeout(() => { refreshing = null; }, 0); });
  }
  return refreshing;
}

export async function ensureSession() {
  if (access && tokenExp(access) - Date.now() > 30_000) return true;
  if (!hasSessionHint()) return false;
  return refreshSession();
}

/** Запрос к API. json — тело; form — FormData (загрузка файлов). Сам обновит токен при 401. */
export async function api(path, { method = 'GET', json, form, auth = true, retry = true } = {}) {
  const headers = { 'X-Session': 'cookie' };
  if (json !== undefined) headers['Content-Type'] = 'application/json';
  if (auth && (access || await ensureSession())) headers.Authorization = `Bearer ${access}`;
  const res = await fetch(`/api/v1${path}`, {
    method, headers, credentials: 'same-origin',
    body: json !== undefined ? JSON.stringify(json) : form,
  });
  if (res.status === 401 && auth && retry && hasSessionHint()) {
    if (await refreshSession()) return api(path, { method, json, form, auth, retry: false });
  }
  if (!res.ok) throw await errorFrom(res);
  if (res.status === 204) return null;
  const ct = res.headers.get('content-type') || '';
  return ct.includes('json') ? res.json() : res.text();
}

export function acceptTokens(data) {
  storeAccess(data.access_token);
  setSessionHint(true);
  window.dispatchEvent(new CustomEvent('session'));
}

export async function logout(everywhere = false) {
  try { await api(everywhere ? '/auth/logout-all' : '/auth/logout', { method: 'POST', json: {} }); } catch { /* всё равно выходим */ }
  storeAccess(null);
  setSessionHint(false);
  location.href = '/';
}

let mePromise = null;
export function me() {
  if (!mePromise) mePromise = ensureSession().then((ok) => (ok ? api('/auth/me').catch(() => null) : null));
  return mePromise;
}

export async function requireLogin() {
  const user = await me();
  if (!user) {
    location.href = `/login?next=${encodeURIComponent(location.pathname + location.hash)}`;
    return new Promise(() => {}); // страница уходит
  }
  return user;
}

// Код друга из ссылки ?ref=… — помним 30 дней, отправляем при регистрации
const REF_KEY = 'ref_v1';
const refParam = new URLSearchParams(location.search).get('ref');
if (refParam && /^[A-Z0-9]{4,16}$/i.test(refParam)) {
  try { localStorage.setItem(REF_KEY, JSON.stringify({ code: refParam.toUpperCase(), until: Date.now() + 30 * 864e5 })); } catch { /* приватный режим */ }
}
export function referralCode() {
  try {
    const r = JSON.parse(localStorage.getItem(REF_KEY));
    return r && r.until > Date.now() ? r.code : null;
  } catch { return null; }
}

// Хранится в браузере (работает и без входа). Цены — подсказка; итог всегда пересчитывает сервер.
const CART_KEY = 'cart_v1';

function readCart() {
  try { return JSON.parse(localStorage.getItem(CART_KEY)) || {}; } catch { return {}; }
}

function writeCart(c) {
  try { localStorage.setItem(CART_KEY, JSON.stringify(c)); } catch { /* приватный режим */ }
  window.dispatchEvent(new CustomEvent('cart', { detail: c }));
}

export const cart = {
  all: () => readCart(),
  /** [{id, name, price, image, unit, url, qty, stock}] */
  lines: () => Object.values(readCart()),
  qty: (id) => readCart()[id]?.qty || 0,
  count: () => Object.values(readCart()).reduce((a, l) => a + l.qty, 0),
  total: () => Object.values(readCart()).reduce((a, l) => a + l.qty * l.price, 0),
  set(product, qty) {
    const c = readCart();
    const max = Math.min(product.stock ?? 999, 999);
    if (qty <= 0) delete c[product.id];
    else c[product.id] = { ...(c[product.id] || {}), ...product, qty: Math.min(qty, max) };
    writeCart(c);
    if (qty > max) toast(`Больше ${max} шт. нет в наличии`);
  },
  add(product, n = 1) { this.set(product, this.qty(product.id) + n); },
  clear() { writeCart({}); },
};

// Корзина в другой вкладке изменилась — синхронизируемся
window.addEventListener('storage', (e) => { if (e.key === CART_KEY) window.dispatchEvent(new CustomEvent('cart')); });

const ds = document.body.dataset;
export const DELIVERY = {
  courier: { label: 'Курьер', fee: Number(ds.courierFee), on: true },
  express: { label: ds.expressLabel, fee: Number(ds.expressFee), on: ds.expressOn === '1' },
  pickup: { label: 'Самовывоз', fee: 0, on: ds.pickupOn === '1' },
};
export const MIN_ORDER = Number(ds.minOrder) || 0;
export const FREE_FROM = ds.freeFrom === '' ? null : Number(ds.freeFrom); // null — курьер всегда платный
export const deliveryFee = (kind, goods) => {
  if (kind === 'pickup') return 0;
  if (kind === 'courier' && FREE_FROM !== null && goods >= FREE_FROM) return 0;
  return DELIVERY[kind].fee;
};
/** Почему с такой суммой этим способом не оформить (null — можно). Сервер проверяет то же самое. */
export const deliveryProblem = (kind, goods) => (kind !== 'pickup' && goods < MIN_ORDER
  ? `Доставка — при заказе от ${rub(MIN_ORDER)}. Добавьте товаров ещё на ${rub(MIN_ORDER - goods)}`
  : null);
