/// Те же правила, что и на сервере (app/core/security.py → password_problem).
/// Клиентская проверка — для удобства; настоящая защита всегда на сервере.
const _common = {
  'password1', 'password123', 'qwerty123', 'qwerty12', 'qwertyuiop1', //
  '1q2w3e4r', '1q2w3e4r5t', '1qaz2wsx', 'zaq12wsx', 'abc12345', 'abcd1234',
  'admin123', 'admin1234', 'iloveyou1', 'welcome1', 'passw0rd', 'p@ssw0rd',
  'letmein1', '11111111a', 'a1234567', 'a12345678', 'q1w2e3r4', 'q1w2e3r4t5',
  'parol123', 'privet123', 'qwe12345', 'asdf1234', 'test1234', 'user1234',
  '1234qwer', '12345qwe', '123456789a', '123qweasd', 'qweasd123', 'qazwsx123',
  'pass1234', 'monkey123', 'dragon123', 'football1', 'baseball1',
};

final _letter = RegExp(r'[A-Za-zА-Яа-яЁё]');
final _digit = RegExp(r'\d');

String? passwordProblem(String password, {String? email}) {
  if (password.length < 8) return 'Минимум 8 символов';
  if (password.length > 128) return 'Слишком длинный пароль';
  if (!_letter.hasMatch(password) || !_digit.hasMatch(password)) {
    return 'Нужны и буквы, и цифры';
  }
  if (_common.contains(password.toLowerCase()) ||
      password.split('').toSet().length < 4) {
    return 'Слишком простой пароль — его легко подобрать';
  }
  final local = (email ?? '').split('@').first.toLowerCase();
  if (local.length >= 4 && password.toLowerCase().contains(local)) {
    return 'Пароль не должен содержать ваш email';
  }
  return null;
}

/// 0..4 — для полоски надёжности под полем пароля.
int passwordScore(String p, {String? email}) {
  if (p.isEmpty) return 0;
  if (passwordProblem(p, email: email) != null) return 1;
  var score = 2;
  if (p.length >= 12) score++;
  if (RegExp(r'[^A-Za-zА-Яа-яЁё0-9]').hasMatch(p) ||
      (RegExp(r'[a-zа-яё]').hasMatch(p) && RegExp(r'[A-ZА-ЯЁ]').hasMatch(p))) {
    score++;
  }
  return score.clamp(0, 4);
}
