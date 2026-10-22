import { $, api, esc, icon, me } from './core.js';

const root = $('[data-b2b]');
const state = $('[data-b2b-state]', root);
const form = $('[data-b2b-form]', root);

const STATUS = {
  pending: ['check', 'Заявка на проверке', 'Обычно проверяем в течение рабочего дня. Как только подключим прайс, оптовые цены появятся в корзине.'],
  approved: ['shield', 'Оптовые цены подключены', 'Цены по вашему прайсу применяются в корзине и при оформлении заказа.'],
  suspended: ['x', 'Оптовые цены приостановлены', 'Свяжитесь с нами, чтобы возобновить работу.'],
  rejected: ['x', 'Заявка отклонена', 'Проверьте данные и отправьте заявку ещё раз или свяжитесь с нами.'],
};

function showStatus(b2b) {
  const [ic, title, text] = STATUS[b2b.status] || STATUS.pending;
  state.innerHTML = `<div class="biz-status">${icon(ic)}<div><b>${esc(title)}</b>
    <p class="muted">${esc(b2b.legal_name)}</p><p>${esc(text)}</p></div></div>`;
  form.hidden = b2b.status !== 'rejected';
  if (b2b.status === 'rejected') form.legal_name.value = b2b.legal_name;
}

const user = await me();
if (!user) {
  state.innerHTML = `<p>Войдите по номеру телефона — заявка привяжется к вашему аккаунту, и мы сможем с вами связаться.</p>
    <a class="btn btn--primary btn--lg" href="/login?next=${encodeURIComponent('/business#apply')}">Войти и оставить заявку</a>`;
} else if (user.is_staff) {
  state.innerHTML = '<p class="muted">Вы вошли как сотрудник магазина. Заявки на оптовые цены подают покупатели.</p>';
} else if (user.b2b) {
  showStatus(user.b2b);
} else {
  state.innerHTML = '';
  form.hidden = false;
}

form.tax_id.addEventListener('input', () => {
  form.tax_id.value = form.tax_id.value.replace(/\D/g, '').slice(0, 12);
});

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const err = $('[data-error]', form);
  err.hidden = true;
  const name = form.legal_name.value.trim();
  const inn = form.tax_id.value.trim();
  const problem = name.length < 2 ? 'Укажите название компании'
    : ![10, 12].includes(inn.length) ? 'ИНН — 10 цифр у компании, 12 — у ИП' : '';
  if (problem) {
    err.textContent = problem;
    err.hidden = false;
    return;
  }
  const btn = form.querySelector('[type=submit]');
  btn.disabled = true;
  try {
    showStatus(await api('/me/b2b-application', { method: 'POST', json: { legal_name: name, tax_id: inn } }));
  } catch (ex) {
    err.textContent = ex.message;
    err.hidden = false;
  } finally {
    btn.disabled = false;
  }
});
