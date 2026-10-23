import { $, $$ } from './core.js';

const root = $('[data-banners]');
const track = $('[data-track]', root);
const dots = $$('[data-dot]', root);
let index = 0;
let timer = null;

function go(i) {
  index = (i + dots.length) % dots.length;
  track.scrollTo({ left: track.clientWidth * index, behavior: 'smooth' });
}
function mark() {
  index = Math.round(track.scrollLeft / track.clientWidth);
  dots.forEach((d, n) => d.classList.toggle('is-active', n === index));
}
const play = () => { clearInterval(timer); timer = setInterval(() => go(index + 1), 6000); };

dots.forEach((d) => d.addEventListener('click', () => { go(Number(d.dataset.dot)); play(); }));
track.addEventListener('scroll', () => requestAnimationFrame(mark), { passive: true });
root.addEventListener('pointerenter', () => clearInterval(timer));
root.addEventListener('pointerleave', play);
mark();
if (!matchMedia('(prefers-reduced-motion: reduce)').matches) play();
