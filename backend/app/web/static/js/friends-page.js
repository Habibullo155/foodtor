import { $, api, esc, icon, me, rub, toast } from './core.js';

const box = $('[data-friends]');
const user = await me();

if (!user) {
  box.innerHTML = `<div class="friends-box__login"><p><b>Войдите, чтобы получить свою ссылку</b></p>
    <a class="btn btn--primary" href="/login?next=${encodeURIComponent('/friends')}">Войти по номеру телефона</a></div>`;
} else {
  const r = await api('/me/referral');
  const link = `${location.origin}/?ref=${r.code}`;
  const promos = r.promos.filter((p) => !p.used);
  box.innerHTML = `
    <h2>Ваша ссылка</h2>
    <div class="share">
      <input class="input" value="${esc(link)}" readonly data-link aria-label="Ссылка для друга">
      <button class="btn btn--primary" type="button" data-copy>${icon('copy')} Скопировать</button>
      ${navigator.share ? `<button class="btn btn--ghost" type="button" data-share>Поделиться</button>` : ''}
    </div>
    <p class="muted small">Или продиктуйте код: <b class="code">${esc(r.code)}</b></p>
    <div class="friends-stats">
      <div><b>${r.invited}</b><span>друзей пришло</span></div>
      <div><b>${r.rewarded}</b><span>сделали заказ</span></div>
    </div>
    <h2>Мои промокоды</h2>
    ${promos.length ? `<ul class="promo-list">${promos.map((p) => `<li>
        <b class="code">${esc(p.code)}</b>
        <span>−${rub(p.amount)} на заказ от ${rub(p.min_order)}${p.first_order_only ? ' · только на первый заказ' : ''}</span>
        <button class="link" type="button" data-copy-code="${esc(p.code)}">Скопировать</button></li>`).join('')}</ul>
        <p class="muted small">Введите промокод в корзине перед оформлением заказа.</p>`
      : '<p class="muted">Пока нет — пригласите друга, и промокод появится здесь.</p>'}`;

  const copy = async (text) => {
    try { await navigator.clipboard.writeText(text); toast('Скопировано'); } catch { $('[data-link]', box).select(); }
  };
  box.addEventListener('click', (e) => {
    if (e.target.closest('[data-copy]')) copy(link);
    const code = e.target.closest('[data-copy-code]');
    if (code) copy(code.dataset.copyCode);
    if (e.target.closest('[data-share]')) {
      navigator.share({ title: document.title, text: r.friend_amount > 0 ? `Дарю ${rub(r.friend_amount)} на первый заказ свежих продуктов` : 'Свежие продукты с доставкой', url: link }).catch(() => {});
    }
  });
}
