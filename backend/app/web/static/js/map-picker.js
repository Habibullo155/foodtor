import { $, api, debounce, esc } from './core.js';

/* global L */
let zonePromise = null;
const zone = () => (zonePromise ||= api('/delivery/zone', { auth: false }).catch(() => null));

export function pickLocation({ lat, lng } = {}) {
  const dlg = $('[data-map-dialog]');
  const addrEl = $('[data-map-address]', dlg);
  const verdictEl = $('[data-map-verdict]', dlg);
  const ok = $('[data-map-ok]', dlg);
  let map;
  let current = null;

  return new Promise((resolve) => {
    const finish = (value) => {
      dlg.close();
      map?.remove();
      resolve(value);
    };

    const resolvePoint = debounce(async () => {
      const c = map.getCenter();
      ok.disabled = true;
      addrEl.textContent = 'Определяем адрес…';
      verdictEl.textContent = '';
      const [rev, check] = await Promise.all([
        api(`/delivery/reverse?lat=${c.lat}&lng=${c.lng}`, { auth: false }).catch(() => ({ address: null })),
        api('/delivery/check', { method: 'POST', json: { lat: c.lat, lng: c.lng }, auth: false }).catch(() => ({ ok: true })),
      ]);
      current = { lat: c.lat, lng: c.lng, address: rev.address, city: rev.city, street: rev.street, house: rev.house };
      addrEl.textContent = rev.address
        ? [rev.city, rev.street, rev.house ? `дом ${rev.house}` : 'дом не определён'].filter(Boolean).join(' · ')
        : 'Адрес не определён — уточните его в форме';
      verdictEl.className = `small ${check.ok ? 'good' : 'error'}`;
      verdictEl.textContent = check.ok
        ? `Сюда доставляем${check.distance_km != null ? ` · ${check.distance_km} км от склада` : ''}`
        : `Мы не доставляем по вашему адресу. ${check.reason || ''}`;
      ok.disabled = !check.ok;
      ok.textContent = check.ok ? 'Доставить сюда' : 'Сюда не доставляем';
    }, 500);

    dlg.showModal();
    let markReady;
    const ready = new Promise((r) => { markReady = r; });
    zone().then((z) => {
      const start = lat != null ? [lat, lng] : z ? [z.lat, z.lng] : [55.7558, 37.6176];
      map = L.map($('[data-map]', dlg), { zoomControl: true, attributionControl: true }).setView(start, lat != null ? 16 : 11);
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19, attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      }).addTo(map);
      if (z?.enabled) {
        L.circle([z.lat, z.lng], { radius: z.radius_km * 1000, color: '#0B5D3B', weight: 2, fillOpacity: 0.06, interactive: false }).addTo(map);
      }
      map.on('moveend', resolvePoint);
      resolvePoint();
      markReady();
    });

    const locateBtn = $('[data-map-locate]', dlg);
    const geoEl = $('[data-map-geo]', dlg);
    geoEl.hidden = true;
    const geoNote = (text) => { geoEl.textContent = text; geoEl.hidden = false; };
    const locate = (auto = false) => {
      if (!window.isSecureContext || !navigator.geolocation) {
        if (!auto) geoNote('Определить местоположение можно только на защищённом сайте (https). Передвиньте карту к своему дому.');
        return;
      }
      locateBtn.disabled = true;
      locateBtn.lastChild.textContent = ' Определяем…';
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          locateBtn.disabled = false;
          locateBtn.lastChild.textContent = ' Моё местоположение';
          geoEl.hidden = true;
          const go = () => map.setView([pos.coords.latitude, pos.coords.longitude], 17);
          map ? go() : ready.then(go);
        },
        (err) => {
          locateBtn.disabled = false;
          locateBtn.lastChild.textContent = ' Моё местоположение';
          if (auto && err.code !== err.PERMISSION_DENIED) return; // тихо: человек сам передвинет карту
          geoNote(err.code === err.PERMISSION_DENIED
            ? 'Доступ к местоположению запрещён. Разрешите его в настройках браузера (значок слева от адреса сайта) или передвиньте карту к своему дому.'
            : 'Не удалось определить местоположение — передвиньте карту к своему дому.');
        },
        { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 },
      );
    };
    locateBtn.onclick = () => locate(false);
    // Новая точка — сразу спрашиваем браузер о местоположении (откажут — просто двигаем карту вручную)
    if (lat == null) locate(true);
    ok.onclick = () => finish(current);
    $('[data-map-close]', dlg).onclick = () => finish(null);
    dlg.oncancel = (e) => { e.preventDefault(); finish(null); };
  });
}

/** Проверка, что в адресе есть улица и дом (как на сервере). null — всё хорошо. */
const HOUSE = /(^|[^\p{L}\p{N}])\d+[а-яa-z]?(\s*[/к]\s*\d+)?(?![\p{L}\p{N}])/iu;
const NOT_STREET = new Set(['москва', 'город', 'россия', 'область', 'дом', 'корпус', 'строение', 'квартира', 'подъезд', 'этаж']);
export function addressProblem(text, cities = []) {
  const t = String(text || '').toLowerCase().replace(/ё/g, 'е');
  const msg = 'Укажите улицу и номер дома — или выберите точку на карте';
  if (!HOUSE.test(t)) return msg;
  const skip = new Set([...NOT_STREET, ...cities.map((c) => c.toLowerCase().replace(/ё/g, 'е'))]);
  return (t.match(/[а-яa-z]{3,}/g) || []).some((w) => !skip.has(w)) ? null : msg;
}

export const zoneInfo = zone;
export { esc };
