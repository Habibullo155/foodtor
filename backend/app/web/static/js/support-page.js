import { $, api, esc, me } from './core.js';

const root = $('[data-support]');
const body = $('[data-support-body]', root);
const form = $('[data-support-form]', root);
const time = (iso) => new Date(iso).toLocaleString('ru-RU', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

function render(messages) {
  const atBottom = body.scrollHeight - body.scrollTop - body.clientHeight < 40;
  body.innerHTML = messages.length
    ? messages.map((m) => `<div class="bubble ${m.from_staff ? '' : 'bubble--mine'}">
        ${m.from_staff ? `<b class="bubble__who">${esc(m.author)} · поддержка</b>` : ''}
        <p>${esc(m.text)}</p><time>${time(m.created_at)}</time></div>`).join('')
    : `<div class="support__empty"><p><b>Здравствуйте!</b></p><p class="muted">Напишите, чем помочь: вопрос о заказе, доставке, оплате или пожелание по ассортименту.</p></div>`;
  if (atBottom || !messages.length) body.scrollTop = body.scrollHeight;
}

const user = await me();
if (!user) {
  body.innerHTML = `<div class="support__empty"><p><b>Войдите, чтобы написать нам</b></p>
    <p class="muted">Так мы увидим ваши заказы и ответим быстрее. Вход — по номеру телефона, без пароля.</p>
    <a class="btn btn--primary" href="/login?next=${encodeURIComponent('/support')}">Войти</a></div>`;
} else {
  form.hidden = false;
  render(await api('/me/support'));
  setInterval(async () => {
    if (document.hidden || document.activeElement === form.text) return;
    try { render(await api('/me/support')); } catch { /* сеть — попробуем позже */ }
  }, 10000);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const text = form.text.value.trim();
    if (!text) return;
    const btn = form.querySelector('[type=submit]');
    btn.disabled = true;
    try {
      render(await api('/me/support', { method: 'POST', json: { text } }));
      form.text.value = '';
      body.scrollTop = body.scrollHeight;
    } catch (err) {
      form.insertAdjacentHTML('beforeend', `<p class="error small">${esc(err.message)}</p>`);
    } finally {
      btn.disabled = false;
    }
  });
  form.text.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) form.requestSubmit();
  });
}
