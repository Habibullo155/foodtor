import { $, $$, api, cart, debounce, DELIVERY, esc, icon, requireLogin, rub, toast } from './core.js';
import { addressProblem, pickLocation, zoneInfo } from './map-picker.js';
import { attachPhoneMask, phoneComplete } from './phone.js';

const form = $('[data-checkout]');
const user = await requireLogin();
const prefs = (() => { try { return JSON.parse(sessionStorage.getItem('cart_prefs')) || {}; } catch { return {}; } })();

if (!cart.count()) location.replace('/cart');

let addresses = [];
let savedId = null; // выбран сохранённый адрес
let point = null; // {lat, lng} — выбрано на карте
let zone = null; // ответ /delivery/check для текущего адреса
let zoneFor = '';
let cities = [];

form.name.value = user.full_name || '';
form.phone.value = user.phone || '';
attachPhoneMask(form.phone);
const kind = () => form.querySelector('[name=delivery]:checked').value;
$$('[name=delivery]', form).forEach((r) => { r.checked = r.value === (prefs.delivery || 'courier'); });

function fullAddress() {
  if (kind() === 'pickup') return 'Самовывоз';
  const a = addresses.find((x) => x.id === savedId);
  if (a) return [a.one_line, a.courier_note ? `курьеру: ${a.courier_note}` : ''].filter(Boolean).join('; ');
  const parts = [form.address.value.trim()];
  if (form.apartment.value.trim()) parts.push(`кв. ${form.apartment.value.trim()}`);
  if (form.entrance.value.trim()) parts.push(`подъезд ${form.entrance.value.trim()}`);
  if (form.floor.value.trim()) parts.push(`этаж ${form.floor.value.trim()}`);
  return parts.join(', ');
}

function targetPoint() {
  const a = addresses.find((x) => x.id === savedId);
  if (a) return a.lat != null ? { lat: a.lat, lng: a.lng } : null;
  return point;
}

function renderSaved() {
  const box = $('[data-saved-addresses]', form);
  if (!addresses.length) { box.innerHTML = ''; return; }
  box.innerHTML = addresses.map((a) => `
    <label class="addr"><input type="radio" name="saved" value="${a.id}" ${a.id === savedId ? 'checked' : ''}>
      <span><b>${esc(a.label)}</b><span class="muted small">${esc(a.one_line)}</span></span></label>`).join('') +
    `<label class="addr"><input type="radio" name="saved" value="" ${savedId == null ? 'checked' : ''}><span><b>Другой адрес</b></span></label>`;
  $$('[name=saved]', box).forEach((r) => r.addEventListener('change', () => {
    savedId = r.value ? Number(r.value) : null;
    syncAddressFields();
    checkZone(true);
  }));
}

function syncAddressFields() {
  const manual = savedId == null;
  $$('[name=address], [name=apartment], [name=entrance], [name=floor]', form).forEach((i) => { i.closest('.field').hidden = !manual; });
  $('[data-pick-map]', form).hidden = !manual;
  const save = $('[data-save-address]', form)?.closest('label');
  if (save) save.hidden = !manual;
  $('[data-address-block]', form).hidden = kind() === 'pickup';
}

function renderZone(loading = false) {
  const el = $('[data-zone]', form);
  if (kind() === 'pickup') { el.hidden = true; return; }
  if (loading) { el.hidden = false; el.className = 'zone'; el.innerHTML = '<span class="muted small">Проверяем адрес…</span>'; return; }
  if (!zone) { el.hidden = true; return; }
  el.hidden = false;
  const needs = !zone.ok && /номер дома|Не нашли/.test(zone.reason || '');
  if (zone.ok) {
    el.className = 'zone zone--ok';
    el.innerHTML = `${icon('check')} Доставляем по этому адресу`;
  } else if (needs) {
    el.className = 'zone zone--warn';
    el.innerHTML = `${icon('pin')} <span>${esc(zone.reason)}</span>`;
  } else {
    el.className = 'zone zone--bad';
    el.innerHTML = `<b>Мы не доставляем по вашему адресу</b><span>${esc(zone.reason || '')}</span>
      <button class="btn btn--ghost btn--sm" type="button" data-to-pickup>${icon('store')} Заберу сам — самовывоз</button>`;
  }
}

async function checkZone(now = false) {
  if (kind() === 'pickup') { zone = null; renderZone(); return; }
  const text = savedId == null ? form.address.value.trim() : fullAddress();
  const p = targetPoint();
  const key = p ? `${p.lat},${p.lng}` : text;
  if (!p && savedId == null) {
    const problem = text.length >= 3 ? addressProblem(text, cities) : null;
    if (problem) { zone = { ok: false, reason: problem }; zoneFor = key; renderZone(); updateSubmit(); return; }
    if (text.length < 5) { zone = null; renderZone(); updateSubmit(); return; }
  }
  if (key === zoneFor && zone) return;
  renderZone(true);
  const run = async () => {
    const body = p ? { lat: p.lat, lng: p.lng } : { address: text };
    try { zone = await api('/delivery/check', { method: 'POST', json: body, auth: false }); } catch { zone = { ok: true }; }
    zoneFor = key;
    renderZone();
    updateSubmit();
  };
  now ? run() : debouncedRun(run);
}
const debouncedRun = debounce((f) => f(), 700);

form.address.addEventListener('input', () => { point = null; $('[data-picked]', form)?.remove(); checkZone(); });

/** Что подставилось с карты — крупно, чтобы покупатель проверил; без номера дома — просим уточнить. */
function showPicked(p) {
  $('[data-picked]', form)?.remove();
  const box = document.createElement('div');
  box.className = `picked ${p.house ? '' : 'picked--warn'}`;
  box.dataset.picked = '';
  box.innerHTML = `${icon('pin')}<div><b>${esc(p.address || 'Точка на карте')}</b>
    <span class="small">${p.house ? 'Адрес заполнен — проверьте его и укажите квартиру, подъезд и этаж'
      : 'Номер дома не определился — допишите его в поле «Адрес доставки»'}</span></div>`;
  $('[data-pick-map]', form).before(box);
  for (const f of [form.address, form.apartment]) f.classList.add('is-filled');
  setTimeout(() => [form.address, form.apartment].forEach((f) => f.classList.remove('is-filled')), 1600);
  (p.house ? form.apartment : form.address).focus();
}
$('[data-pick-map]', form).addEventListener('click', async () => {
  const picked = await pickLocation(point || {});
  if (!picked) return;
  point = { lat: picked.lat, lng: picked.lng };
  if (picked.address) form.address.value = picked.address;
  $('[data-pick-map] span', form).textContent = 'Точка на карте выбрана — изменить';
  showPicked(picked);
  zoneFor = '';
  checkZone(true);
});
form.addEventListener('click', (e) => {
  if (e.target.closest('[data-to-pickup]')) {
    form.querySelector('[name=delivery][value=pickup]').checked = true;
    onDeliveryChange();
  }
});

let quoteSeq = 0;
async function renderSummary() {
  const lines = cart.lines();
  $('[data-summary-lines]', form).innerHTML = lines.map((l) =>
    `<div class="mini-line"><span>${esc(l.name)} <span class="muted">× ${l.qty}</span></span><b>${rub(l.qty * l.price)}</b></div>`).join('');
  const seq = ++quoteSeq;
  try {
    const q = await api('/me/orders/quote', { method: 'POST', json: {
      items: lines.map((l) => ({ product_id: l.id, quantity: l.qty })), delivery: kind(), promo_code: prefs.promo || null,
    } });
    if (seq !== quoteSeq) return;
    const row = (k, v, cls = '') => `<div class="${cls}"><dt>${k}</dt><dd>${v}</dd></div>`;
    $('[data-totals]', form).innerHTML =
      row('Товары', rub(q.subtotal)) +
      (+q.loyalty_discount ? row(`Скидка ${esc(q.tier_name || '')}`, '−' + rub(q.loyalty_discount), 'good') : '') +
      (+q.promo_discount ? row('Промокод', '−' + rub(q.promo_discount), 'good') : '') +
      row(DELIVERY[kind()].label, +q.delivery_fee ? rub(q.delivery_fee) : 'бесплатно', +q.delivery_fee ? '' : 'good') +
      row('К оплате', rub(q.total), 'total');
    if (q.promo_error) toast(q.promo_error);
  } catch (e) { showError(e.message); }
}

function showError(msg) {
  const el = $('[data-error]', form);
  el.textContent = msg || '';
  el.hidden = !msg;
}

function blocked() { return kind() !== 'pickup' && zone && !zone.ok; }
function updateSubmit() {
  $('[data-submit]', form).disabled = blocked();
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  showError('');
  if (form.name.value.trim().length < 2) return showError('Укажите имя получателя');
  if (!phoneComplete(form.phone.value)) return showError('Введите телефон полностью: +7 (9XX) XXX-XX-XX');
  if (kind() !== 'pickup') {
    if (savedId == null && !point) {
      const problem = addressProblem(form.address.value, cities);
      if (problem) return showError(problem);
    }
    await checkZone(true);
    if (blocked()) return showError(zone.reason || 'Мы не доставляем по этому адресу');
  }
  const btn = $('[data-submit]', form);
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner spinner--sm"></span>';
  try {
    const p = kind() === 'pickup' ? null : targetPoint();
    if (kind() !== 'pickup' && savedId == null && $('[data-save-address]')?.checked) {
      api('/me/addresses', { method: 'POST', json: {
        label: addresses.length ? 'Другое' : 'Дом', address: form.address.value.trim(),
        apartment: form.apartment.value.trim() || null, entrance: form.entrance.value.trim() || null,
        floor: form.floor.value.trim() || null, lat: p?.lat ?? null, lng: p?.lng ?? null,
      } }).catch(() => {}); // адрес не сохранился — заказ всё равно оформляем
    }
    const order = await api('/me/orders', { method: 'POST', json: {
      items: cart.lines().map((l) => ({ product_id: l.id, quantity: l.qty })),
      delivery: kind(), name: form.name.value.trim(), phone: form.phone.value.trim(), address: fullAddress(),
      lat: p?.lat ?? null, lng: p?.lng ?? null, payment: form.querySelector('[name=payment]:checked').value,
      note: form.note.value.trim() || null, promo_code: prefs.promo || null,
    } });
    cart.clear();
    try { sessionStorage.removeItem('cart_prefs'); } catch { /* ok */ }
    location.href = order.pay_url || `/account#order-${order.id}`;
  } catch (err) {
    showError(err.message);
    btn.textContent = 'Оформить заказ';
    updateSubmit();
    renderSummary();
  }
});

function onDeliveryChange() {
  prefs.delivery = kind();
  try { sessionStorage.setItem('cart_prefs', JSON.stringify(prefs)); } catch { /* ok */ }
  syncAddressFields();
  checkZone(true);
  renderSummary();
  updateSubmit();
}
$$('[name=delivery]', form).forEach((r) => r.addEventListener('change', onDeliveryChange));

const [saved, z] = await Promise.all([
  api('/me/addresses').catch(() => []),
  zoneInfo(),
]);
cities = z?.cities || [];
addresses = saved;
const def = addresses.find((a) => a.is_default) || addresses[0];
savedId = def ? def.id : null;
const saveBox = document.createElement('label');
saveBox.className = 'check';
saveBox.innerHTML = '<input type="checkbox" data-save-address checked> Сохранить в «Мои адреса»';
$('[data-pick-map]', form).after(saveBox);
renderSaved();
syncAddressFields();
checkZone(true);
renderSummary();
updateSubmit();
