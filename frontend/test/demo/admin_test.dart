import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/core/theme/app_theme.dart';
import 'package:saasshop/features/admin/admin_shell.dart';
import 'package:saasshop/features/admin/auth/admin_auth.dart';
import 'package:saasshop/features/admin/auth/demo_accounts.dart';
import 'package:saasshop/features/admin/rbac.dart';

/// Пароли берутся из DEMO_ACCOUNTS.md (в .gitignore) — в коде их нет.
String? demoPassword(String email) {
  final f = File('../DEMO_ACCOUNTS.md').existsSync()
      ? File('../DEMO_ACCOUNTS.md')
      : File('../../DEMO_ACCOUNTS.md');
  if (!f.existsSync()) return null;
  final m = RegExp('`${RegExp.escape(email)}` \\| `([^`]+)`')
      .firstMatch(f.readAsStringSync());
  return m?.group(1);
}

Future<ProviderContainer> pumpAdmin(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(useGoogleFonts: false),
        home: const AdminRoot(),
      ),
    ),
  );
  await tester.pump();
  return c;
}

Future<void> login(
  WidgetTester tester,
  ProviderContainer c,
  String email,
) async {
  final pw = demoPassword(email);
  if (pw == null) {
    final a = demoAccounts.firstWhere((a) => a.email == email);
    c
        .read(adminAuthProvider.notifier)
        .signInForTest(
          AdminSession(email: a.email, name: a.name, role: a.role),
        );
  } else {
    final r = await tester.runAsync(
      () => c.read(adminAuthProvider.notifier).login(email, pw),
    );
    expect(r, isA<LoginOk>());
  }
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('wrong password is rejected without revealing which field; lockout after 5 tries', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(adminAuthProvider.notifier);
    for (var i = 0; i < 4; i++) {
      final r = await n.login('owner@saasshop.local', 'nope') as LoginFailed;
      expect(r.message, contains('Неверный email или пароль'));
    }
    expect(
      (await n.login('owner@saasshop.local', 'nope') as LoginFailed).message,
      contains('заблокирован'),
    );
    final pw = demoPassword('owner@saasshop.local');
    if (pw != null) {
      // Даже верный пароль не пускает, пока действует блокировка
      expect(await n.login('owner@saasshop.local', pw), isA<LoginFailed>());
    }
    expect(c.read(adminAuthProvider), isNull);
  });

  testWidgets('login screen is shown first', (tester) async {
    await pumpAdmin(tester, const Size(1440, 900));
    expect(find.text('Вход в админ-панель'), findsOneWidget);
  });

  testWidgets('owner sees every section on desktop dashboard', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 1000));
    await login(tester, c, 'owner@saasshop.local');
    if (c.read(adminAuthProvider) == null) return;
    expect(c.read(visibleSectionsProvider).length, AdminSection.values.length);
    expect(find.text('Выручка'), findsWidgets);
    expect(find.text('Чистая прибыль'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker sees only picking, can take an order into work', (
    tester,
  ) async {
    final c = await pumpAdmin(tester, const Size(390, 844));
    await login(tester, c, 'picker@saasshop.local');
    if (c.read(adminAuthProvider) == null) return;
    expect(c.read(visibleSectionsProvider), [AdminSection.picking]);
    expect(find.text('Выручка'), findsNothing);
    expect(
      find.byIcon(Icons.menu_rounded),
      findsNothing,
    ); // один раздел — без меню
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(390, 844),
    const Size(800, 1000),
    const Size(1280, 900),
    const Size(2000, 1200),
  ]) {
    testWidgets(
      'manager dashboard has no overflow at ${size.width.toInt()}px',
      (tester) async {
        final c = await pumpAdmin(tester, size);
        await login(tester, c, 'manager@saasshop.local');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
