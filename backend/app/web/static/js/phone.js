// Ввод телефона: «+7» ставится сам, первая 7 или 8 не набирается повторно; формат +7 (916) 123-45-67.
// Принимает и вставку целиком («8 916 123 45 67», «+79161234567»).

/** 10 цифр номера после +7 из любого написания: «8 916…», «+7 916…», «7916…», «916…». */
export function phoneDigits(value) {
  let d = String(value || '').replace(/\D/g, '');
  if (d.length === 11 && (d[0] === '7' || d[0] === '8')) d = d.slice(1);
  return d.slice(0, 10);
}

export function formatPhone(digits) {
  const d = digits.slice(0, 10);
  let out = '+7';
  if (d.length) out += ` (${d.slice(0, 3)}`;
  if (d.length >= 3) out += ')';
  if (d.length > 3) out += ` ${d.slice(3, 6)}`;
  if (d.length > 6) out += `-${d.slice(6, 8)}`;
  if (d.length > 8) out += `-${d.slice(8, 10)}`;
  return out;
}

export const phoneComplete = (value) => phoneDigits(value).length === 10;

export function attachPhoneMask(input) {
  if (!input || input.dataset.phoneMask) return;
  input.dataset.phoneMask = '1';
  input.type = 'tel';
  input.inputMode = 'tel';
  input.autocomplete = 'tel';
  input.placeholder = '+7 (9XX) XXX-XX-XX';
  input.maxLength = 18;
  let prev = '';
  const apply = () => {
    const v = input.value;
    let d;
    if (v.startsWith('+7')) {
      d = v.slice(2).replace(/\D/g, '');
      if (d.length <= 1) prev = ''; // поле стёрли до «+7 (» — следующая цифра снова первая
      // Первая набранная цифра 7 или 8 — это код страны, он уже стоит: пропускаем
      if (!prev && (d[0] === '7' || d[0] === '8')) d = d.slice(1);
    } else {
      d = phoneDigits(v); // вставили номер целиком
      if (d.length < 10 && (d[0] === '7' || d[0] === '8')) d = d.slice(1);
    }
    d = d.slice(0, 10);
    prev = d;
    input.value = d.length ? formatPhone(d) : '+7 (';
  };
  input.addEventListener('input', apply);
  input.addEventListener('focus', () => { if (!input.value) { input.value = '+7 ('; prev = ''; } });
  input.addEventListener('blur', () => { if (input.value === '+7 (' || input.value === '+7') input.value = ''; });
  input.addEventListener('keydown', (e) => {
    // Backspace по служебному символу («)», «-», пробел) удаляет и цифру перед ним
    if (e.key === 'Backspace' && input.selectionStart === input.value.length && /[\s)(-]$/.test(input.value)) {
      e.preventDefault();
      const d = input.value.slice(2).replace(/\D/g, '').slice(0, -1);
      prev = d;
      input.value = d.length ? formatPhone(d) : '+7 (';
    }
  });
  if (input.value) {
    prev = phoneDigits(input.value);
    input.value = prev.length ? formatPhone(prev) : '';
  }
}
