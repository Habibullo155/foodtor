import 'package:flutter_test/flutter_test.dart';
import 'package:saasshop/features/admin/pages/shop_settings_cards.dart';

void main() {
  test('verification code is taken from a pasted meta tag', () {
    expect(
      verificationCode('<meta name="yandex-verification" content="a1b2c3d4" />'),
      'a1b2c3d4',
    );
    expect(verificationCode('  xY_9-z  '), 'xY_9-z');
    expect(verificationCode(''), '');
  });
}
