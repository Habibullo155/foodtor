// Тема до первой отрисовки (без «мигания» светлой темы). Отдельный файл: CSP запрещает inline-скрипты.
(function () {
  try {
    var t = localStorage.getItem('theme');
    if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t;
  } catch (e) { /* приватный режим — тема по системе */ }
})();
