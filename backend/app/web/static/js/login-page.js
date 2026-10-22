import { $, $$, acceptTokens, api, me } from './core.js';
import { attachPhoneMask, phoneComplete } from './phone.js';

const root = $('[data-auth]');
const next = (() => {
  const n = new URLSearchParams(location.search).get('next') || '/account';
  // только пути этого сайта: «//evil.ru» и «/\evil.ru» браузер считает чужим доменом — открытый редирект
  return /^\/(?![/\\])/.test(n) ? n : '/account';
})();
if (await me()) location.replace(next);

let channel = 'sms'; // sms | email
let target = null;
let signupToken = null;
let timer = null;

const steps = { target: $('[data-step=target]', root), code: $('[data-step=code]', root), name: $('[data-step=name]', root) };
const show = (s) => Object.entries(steps).forEach(([k, el]) => { el.hidden = k !== s; });
const err = (m) => { const e = $('[data-error]', root); e.textContent = m || ''; e.hidden = !m; };
const path = () => (channel === 'sms' ? 'phone' : 'email');

async function busy(form, f) {
  const btn = $('button[type=submit]', form);
  const label = btn.textContent;
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner spinner--sm"></span>';
  err('');
  try { await f(); } catch (e) { err(e.message); } finally { btn.disabled = false; btn.textContent = label; }
}

function done(tokens) {
  acceptTokens(tokens);
  location.replace(next);
}

function setChannel(c) {
  channel = c;
  $$('[data-tab]', root).forEach((t) => t.classList.toggle('is-active', t.dataset.tab === c));
  $('[data-pane=code]', root).hidden = false;
  $('[data-pane=password]', root).hidden = true;
  // Новое поле при каждом переключении: у телефона своя маска, у email — нет
  const old = steps.target.target;
  const input = old.cloneNode(false);
  input.removeAttribute('data-phone-mask');
  input.value = '';
  old.replaceWith(input);
  if (c === 'sms') attachPhoneMask(input);
  else Object.assign(input, { type: 'email', autocomplete: 'email', inputMode: 'email', placeholder: 'name@mail.ru' });
  $('[data-target-label]', root).textContent = c === 'sms' ? 'Номер телефона' : 'Email';
  $('[data-target-hint]', root).textContent = c === 'sms'
    ? 'Пришлём SMS с кодом. Если номера ещё нет у нас — создадим аккаунт.'
    : 'Пришлём письмо с кодом. Если такой почты ещё нет у нас — создадим аккаунт.';
  $('[data-code-label]', root).textContent = c === 'sms' ? 'Код из SMS' : 'Код из письма';
  $('[data-to-password]', root).hidden = c !== 'email';
  show('target');
  err('');
}

function countdown(sec) {
  const btn = $('[data-resend]', root);
  clearInterval(timer);
  let left = sec;
  const tick = () => {
    btn.disabled = left > 0;
    btn.textContent = left > 0 ? `Отправить ещё раз через ${left} с` : 'Отправить ещё раз';
    left -= 1;
    if (left < -1) clearInterval(timer);
  };
  tick();
  timer = setInterval(tick, 1000);
}

async function requestCode(value) {
  const r = await api(`/auth/${path()}/request`, { method: 'POST', json: { [path()]: value }, auth: false });
  target = r.target;
  $('[data-sent-to]', root).textContent = channel === 'sms'
    ? `Код отправлен на ${target}` : `Код отправлен на ${target}. Нет письма — проверьте «Спам».`;
  const dev = $('[data-dev-code]', root);
  dev.hidden = !r.dev_code;
  dev.textContent = r.dev_code ? `Демо: ${channel === 'sms' ? 'SMS' : 'письмо'} не отправляется, ваш код — ${r.dev_code}` : '';
  steps.code.code.value = '';
  show('code');
  steps.code.code.focus();
  countdown(r.resend_in);
}

$$('[data-tab]', root).forEach((t) => t.addEventListener('click', () => setChannel(t.dataset.tab)));
steps.target.addEventListener('submit', (e) => {
  e.preventDefault();
  const value = e.target.target.value.trim();
  if (channel === 'sms' && !phoneComplete(value)) return err('Введите номер полностью: +7 (9XX) XXX-XX-XX');
  if (channel === 'email' && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value)) return err('Проверьте email');
  busy(e.target, () => requestCode(value));
});
steps.code.addEventListener('submit', (e) => {
  e.preventDefault();
  busy(e.target, async () => {
    const r = await api(`/auth/${path()}/verify`, { method: 'POST', json: { [path()]: target, code: e.target.code.value.trim() }, auth: false });
    if (r.status === 'ok') return done(r);
    signupToken = r.signup_token;
    $('[data-confirmed]', root).textContent = `${channel === 'sms' ? 'Номер' : 'Почта'} ${target} подтвержден${channel === 'sms' ? '' : 'а'}.`;
    show('name');
    steps.name.name.focus();
  });
});
// 6-я цифра — проверяем сразу, без нажатия кнопки
steps.code.code.addEventListener('input', (e) => { if (/^\d{6}$/.test(e.target.value)) steps.code.requestSubmit(); });
$('[data-change]', root).addEventListener('click', () => show('target'));
$('[data-resend]', root).addEventListener('click', () => busy(steps.code, () => requestCode(target)));
steps.name.addEventListener('submit', (e) => {
  e.preventDefault();
  busy(e.target, async () => {
    const r = await api(`/auth/${path()}/complete`, { method: 'POST', json: { signup_token: signupToken, full_name: e.target.name.value.trim() }, auth: false });
    done(r);
  });
});

// Пароль (для тех, у кого он есть: сотрудники, старые аккаунты)
$('[data-to-password]', root).addEventListener('click', () => { $('[data-pane=code]', root).hidden = true; $('[data-pane=password]', root).hidden = false; err(''); });
$('[data-to-code]', root).addEventListener('click', () => setChannel('email'));
$('[data-password-form]', root).addEventListener('submit', (e) => {
  e.preventDefault();
  busy(e.target, async () => {
    const body = new URLSearchParams({ username: e.target.email.value.trim(), password: e.target.password.value });
    const res = await fetch('/api/v1/auth/login', { method: 'POST', headers: { 'X-Session': 'cookie' }, body, credentials: 'same-origin' });
    const j = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(j.detail === 'Invalid email or password' ? 'Неверный email или пароль' : (j.detail || 'Не удалось войти'));
    done(j);
  });
});

setChannel('sms');
