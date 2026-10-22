// Карточка товара на JS — та же разметка, что у серверного шаблона _macros.html (product_card).
import { esc, icon, rub } from './core.js';

const TR = { а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'e', ж: 'zh', з: 'z', и: 'i', й: 'y', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'h', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'sch', ъ: '', ы: 'y', ь: '', э: 'e', ю: 'yu', я: 'ya' };

export function slugify(text) {
  const s = [...text.toLowerCase()].map((c) => TR[c] ?? c).join('');
  return s.replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 80) || 'tovar';
}
export const productUrl = (p) => `/product/${p.id}-${slugify(p.name)}`;

export function cartData(p) {
  return {
    id: p.id, name: p.name, price: Number(p.price.price), image: p.image_url, unit: p.unit,
    url: productUrl(p), stock: p.stock_left ?? 999, in_stock: p.in_stock,
  };
}

export function cardHTML(p) {
  const old = p.price.compare_at_price && Number(p.price.compare_at_price) > Number(p.price.price) ? Number(p.price.compare_at_price) : null;
  const url = productUrl(p);
  return `<article class="card" data-product='${esc(JSON.stringify(cartData(p)))}'>
    <a class="card__media" href="${url}" tabindex="-1" aria-hidden="true">
      ${p.image_url ? `<img src="${esc(p.image_url)}" alt="" width="256" height="256" loading="lazy" decoding="async">` : ''}
      <span class="card__badges">
        ${p.badges?.includes('hit') ? '<span class="tag tag--hit">Хит</span>' : ''}
        ${old ? `<span class="tag tag--sale">−${Math.round((1 - Number(p.price.price) / old) * 100)}%</span>` : ''}
      </span>
    </a>
    <div class="card__body">
      <div class="card__meta muted">${esc(p.brand || '')}${p.unit ? ` · ${esc(p.unit)}` : ''}</div>
      <h3 class="card__title"><a href="${url}">${esc(p.name)}</a></h3>
      <div class="card__buy">
        <div class="price"><span class="price__now">${rub(p.price.price)}</span>${old ? `<s class="price__old">${rub(old)}</s>` : ''}</div>
        ${p.in_stock ? `<div class="qty-slot" data-qty-slot><button class="btn btn--primary btn--sm" type="button" data-add>${icon('plus')}<span>В корзину</span></button></div>` : '<span class="muted small">Нет в наличии</span>'}
      </div>
    </div>
  </article>`;
}
