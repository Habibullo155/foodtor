// Страницы рендерятся с розничными ценами (их видят все, в том числе поисковики),
// а подтверждённому оптовику цены подставляются здесь — по его аккаунту.
import { $$, api, esc, me, rub } from './core.js';

let active = null;

export function wholesaleUser() {
  if (!active) active = me().then((u) => (u?.b2b?.status === 'approved' ? u : null));
  return active;
}

function priceHTML(p, withTag) {
  const now = Number(p.price);
  const old = p.compare_at_price && Number(p.compare_at_price) > now ? Number(p.compare_at_price) : null;
  const pct = old ? Math.round((1 - now / old) * 100) : 0;
  const tag = old && withTag ? `<span class="tag ${p.is_wholesale ? 'tag--opt' : 'tag--sale'}">${p.is_wholesale ? 'Опт ' : ''}−${pct}%</span>` : '';
  return { html: `<span class="price__now">${rub(now)}</span>${old ? `<s class="price__old">${rub(old)}</s>` : ''}${tag}`, pct, old };
}

function apply(node, p) {
  const data = JSON.parse(node.dataset.product);
  data.price = Number(p.price);
  node.dataset.product = JSON.stringify(data);
  node.dataset.wholesale = '1';
  const badges = node.querySelector('.card__badges');
  const { html, pct, old } = priceHTML(p, !badges);
  const box = node.querySelector('.price');
  if (box) box.innerHTML = html;
  if (badges) {
    badges.querySelector('.tag--sale, .tag--opt')?.remove();
    if (old) badges.insertAdjacentHTML('afterbegin', `<span class="tag ${p.is_wholesale ? 'tag--opt' : 'tag--sale'}">${p.is_wholesale ? 'Опт ' : ''}−${pct}%</span>`);
  }
}

export async function applyWholesale(root = document) {
  if (!(await wholesaleUser())) return;
  const nodes = $$('[data-product]', root).filter((n) => !n.dataset.wholesale && !n.classList.contains('line'));
  const ids = [...new Set(nodes.map((n) => JSON.parse(n.dataset.product).id))];
  for (let i = 0; i < ids.length; i += 200) {
    const chunk = ids.slice(i, i + 200);
    let r;
    try {
      r = await api(`/products/prices?${chunk.map((id) => `ids=${id}`).join('&')}`);
    } catch {
      return;
    }
    const byId = new Map(r.items.map((it) => [it.id, it.price]));
    nodes.forEach((n) => {
      const p = byId.get(JSON.parse(n.dataset.product).id);
      if (p) apply(n, p);
    });
  }
}

async function banner() {
  const user = await wholesaleUser();
  if (!user) return;
  let min = 0;
  try { min = Number((await api('/shop/options', { auth: false })).wholesale_min_order); } catch { /* без суммы */ }
  const bar = document.querySelector('.delivery-bar');
  bar?.insertAdjacentHTML('afterend', `<div class="wholesale-bar"><div class="wrap">Вам доступны оптовые цены · ${esc(user.b2b.legal_name)}${min ? ` · минимальный заказ ${rub(min)}` : ''}</div></div>`);
}

banner();
applyWholesale();
window.addEventListener('cart-rendered', () => applyWholesale());
