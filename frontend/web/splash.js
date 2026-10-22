// Убирает экран загрузки после первого кадра Flutter.
// Отдельный файл, а не inline-скрипт: строгая CSP (script-src 'self') запрещает inline.
window.addEventListener('flutter-first-frame', function () {
  var s = document.getElementById('splash');
  if (s) s.remove();
});
