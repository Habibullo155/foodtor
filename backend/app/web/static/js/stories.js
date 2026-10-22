import { $, $$, esc } from './core.js';

const stories = JSON.parse($('[data-stories]').textContent);
const dlg = $('[data-story-viewer]');
const SEEN = 'stories_seen';
const DURATION = 5000;
let si = 0; // история
let sl = 0; // слайд
let start = 0;
let elapsed = 0;
let raf = null;
let paused = false;

const seen = () => { try { return new Set(JSON.parse(localStorage.getItem(SEEN)) || []); } catch { return new Set(); } };
function markSeen(key) {
  const s = seen();
  s.add(key);
  try { localStorage.setItem(SEEN, JSON.stringify([...s].slice(-200))); } catch { /* ok */ }
}
function paintRings() {
  const s = seen();
  $$('[data-story]').forEach((b) => {
    const ring = $('.story__ring', b);
    ring.style.setProperty('--story-color', ring.dataset.color);
    b.classList.toggle('is-seen', s.has(b.dataset.storyId));
  });
}

function render() {
  const st = stories[si];
  const slide = st.slides[sl];
  dlg.style.setProperty('--story-color', st.color);
  $('[data-bars]', dlg).innerHTML = st.slides.map((_, i) =>
    `<span class="bar"><i class="${i < sl ? 'is-full' : ''}" ${i === sl ? 'data-active' : ''}></i></span>`).join('');
  $('[data-slide]', dlg).innerHTML = `
    <div class="story-viewer__title">${esc(st.title)}</div>
    <img src="${esc(slide.image)}" alt="" class="story-viewer__img">
    <div class="story-viewer__text"><h2>${esc(slide.headline)}</h2>${slide.caption ? `<p>${esc(slide.caption)}</p>` : ''}
      ${slide.cta_url ? `<a class="btn btn--light btn--lg" href="${esc(slide.cta_url)}">${esc(slide.cta_label)}</a>` : ''}</div>`;
  const key = $(`[data-story="${si}"]`).dataset.storyId;
  markSeen(key);
  elapsed = 0;
  start = performance.now();
}

function tick(now) {
  if (!paused) {
    const p = Math.min(1, (elapsed + now - start) / DURATION);
    const bar = $('[data-active]', dlg);
    if (bar) bar.style.width = `${p * 100}%`;
    if (p >= 1) { next(); }
  }
  raf = requestAnimationFrame(tick);
}

function open(i) {
  si = i; sl = 0; paused = false;
  dlg.showModal();
  render();
  cancelAnimationFrame(raf);
  raf = requestAnimationFrame(tick);
}
function close() {
  cancelAnimationFrame(raf);
  dlg.close();
  paintRings();
}
function next() {
  if (sl < stories[si].slides.length - 1) sl += 1;
  else if (si < stories.length - 1) { si += 1; sl = 0; } else return close();
  render();
}
function prev() {
  if (sl > 0) sl -= 1;
  else if (si > 0) { si -= 1; sl = stories[si].slides.length - 1; }
  render();
}
function pause(on) {
  const now = performance.now();
  if (on && !paused) elapsed += now - start;
  if (!on && paused) start = now;
  paused = on;
}

$$('[data-story]').forEach((b) => b.addEventListener('click', () => open(Number(b.dataset.story))));
$('[data-next]', dlg).addEventListener('click', next);
$('[data-prev]', dlg).addEventListener('click', prev);
$('[data-close]', dlg).addEventListener('click', close);
dlg.addEventListener('cancel', (e) => { e.preventDefault(); close(); });
document.addEventListener('keydown', (e) => {
  if (!dlg.open) return;
  if (e.key === 'ArrowRight') next();
  if (e.key === 'ArrowLeft') prev();
});
// удержание — пауза; свайп вниз — закрыть
let y0 = null;
dlg.addEventListener('pointerdown', (e) => { y0 = e.clientY; pause(true); });
dlg.addEventListener('pointerup', (e) => {
  pause(false);
  if (y0 != null && e.clientY - y0 > 90) close();
  y0 = null;
});
document.addEventListener('visibilitychange', () => pause(document.hidden));
paintRings();
