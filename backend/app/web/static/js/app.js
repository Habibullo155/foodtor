import { $, $$, cart, icon, me, rub, toast } from './core.js';
import './wholesale.js';

function renderHeaderCart() {
  const n = cart.count();
  $$('[data-cart-count]').forEach((b) => { b.textContent = n; b.hidden = n === 0; });
  const total = $('[data-cart-total]');
  if (total) total.textContent = n ? rub(cart.total()) : 'Корзина';
}

async function renderHeaderAccount() {
  const user = await me();
  const label = $('[data-account-label]');
  if (label) label.textContent = user ? (user.full_name.split(' ')[0] || 'Кабинет') : 'Войти';
  if (!user) $$('[data-account-link]').forEach((a) => { a.href = '/login'; });
}

function productOf(el) {
  const host = el.closest('[data-product]');
  return host ? JSON.parse(host.dataset.product) : null;
}

function renderSlot(slot) {
  const p = productOf(slot);
  if (!p) return;
  const q = cart.qty(p.id);
  const big = slot.classList.contains('qty-slot--lg');
  slot.innerHTML = q
    ? `<div class="stepper ${big ? 'stepper--lg' : ''}">
         <button type="button" data-dec aria-label="Убрать одну">${icon('minus')}</button>
         <span aria-live="polite">${q}${big && p.unit ? ` × ${p.unit}` : ''}</span>
         <button type="button" data-inc aria-label="Добавить ещё" ${q >= p.stock ? 'disabled' : ''}>${icon('plus')}</button>
       </div>`
    : `<button class="btn btn--primary ${big ? 'btn--lg btn--block' : 'btn--sm'}" type="button" data-add>${icon(big ? 'cart' : 'plus')}<span>${big ? 'Добавить в корзину' : 'В корзину'}</span></button>`;
}

const renderAllSlots = () => $$('[data-qty-slot]').forEach(renderSlot);

document.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-add], [data-inc], [data-dec]');
  if (!btn) return;
  const p = productOf(btn);
  if (!p) return;
  if (btn.matches('[data-add]')) {
    cart.add(p);
    toast(`«${p.name}» в корзине`);
  } else if (btn.matches('[data-inc]')) cart.add(p);
  else cart.set(p, cart.qty(p.id) - 1);
});

window.addEventListener('cart', () => { renderHeaderCart(); renderAllSlots(); });
window.addEventListener('cart-rendered', renderAllSlots); // страница перерисовала товары

$('[data-theme-toggle]')?.addEventListener('click', () => {
  const root = document.documentElement;
  const current = root.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  const next = current === 'dark' ? 'light' : 'dark';
  root.dataset.theme = next;
  try { localStorage.setItem('theme', next); } catch { /* ok */ }
});

$$('[data-collapsible]').forEach((box) => {
  const key = `collapsed:${box.dataset.collapsible}`;
  const btn = $('[data-collapse-toggle]', box);
  const apply = (closed) => { box.classList.toggle('is-collapsed', closed); btn?.setAttribute('aria-expanded', String(!closed)); };
  let closed = false;
  try { closed = localStorage.getItem(key) === '1'; } catch { /* ok */ }
  apply(closed);
  btn?.addEventListener('click', () => {
    closed = !box.classList.contains('is-collapsed');
    apply(closed);
    try { closed ? localStorage.setItem(key, '1') : localStorage.removeItem(key); } catch { /* ok */ }
  });
});

$('[data-sort]')?.addEventListener('change', (e) => {
  const url = new URL(e.target.dataset.sortTarget || location.href, location.href);
  url.searchParams.set('sort', e.target.value);
  url.searchParams.delete('page');
  location.href = url.toString();
});
$('[data-filters-open]')?.addEventListener('click', () => $('[data-filters]').classList.add('is-open'));
$('[data-filters-close]')?.addEventListener('click', () => $('[data-filters]').classList.remove('is-open'));
// тап мимо панели фильтров (по затемнению) — закрыть
document.addEventListener('click', (e) => {
  const f = $('[data-filters].is-open');
  if (f && !f.contains(e.target) && !e.target.closest('[data-filters-open]')) f.classList.remove('is-open');
});
// Пустые поля цены не попадают в адрес (чище ссылки, лучше для кэша)
$('[data-filter-form]')?.addEventListener('submit', (e) => {
  $$('input[type=number]', e.target).forEach((i) => { if (!i.value) i.disabled = true; });
});
$$('[data-thumb]').forEach((b) => b.addEventListener('click', () => { $('[data-main-image]').src = b.dataset.thumb; }));

renderHeaderCart();
renderAllSlots();
renderHeaderAccount();
