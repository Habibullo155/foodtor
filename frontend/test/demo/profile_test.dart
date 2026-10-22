import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/core/theme/app_theme.dart';
import 'package:saasshop/features/account/customer_session.dart';
import 'package:saasshop/features/account/presentation/profile_page.dart';
import 'package:saasshop/features/catalog/presentation/providers/shop_providers.dart';

Future<ProviderContainer> pumpProfile(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(useGoogleFonts: false),
        home: const Scaffold(body: ProfilePage()),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  return c;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('desktop: sections menu, orders with details and chat', (
    tester,
  ) async {
    await pumpProfile(tester, const Size(1440, 1000));
    for (final s in [
      'Профиль',
      'Мои заказы',
      'История покупок',
      'Мои адреса',
      'Настройки',
    ]) {
      expect(find.text(s), findsWidgets);
    }
    expect(find.text('Заказ 261019-7KQ2'), findsOneWidget);

    await tester.tap(find.text('Заказ 261019-7KQ2'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    // заказ в пути: курьер и чат с ним (телефон скрыт)
    expect(find.text('Курьер Руслан'), findsWidgets);
    expect(find.textContaining('Ваш номер скрыт от курьера'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Переписка по заказу'),
      300,
      scrollable: find
          .ancestor(
            of: find.textContaining('Ваш номер скрыт'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Переписка по заказу'), findsOneWidget);
    expect(find.textContaining('оставьте пакет у двери'), findsOneWidget);
    expect(find.text('Оставьте у двери'), findsWidgets); // быстрые ответы
    expect(tester.takeException(), isNull);
  });

  testWidgets('purchases: buy again adds to cart', (tester) async {
    final c = await pumpProfile(tester, const Size(1440, 1000));
    await tester.tap(find.text('История покупок').first);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.textContaining('Покупали'), findsWidgets);
    await tester.tap(find.byTooltip('В корзину').first);
    await tester.pump();
    expect(c.read(cartProvider), isNotEmpty);
  });

  testWidgets('addresses: default first, profile edit saves name', (
    tester,
  ) async {
    final c = await pumpProfile(tester, const Size(1440, 1000));
    await tester.tap(find.text('Мои адреса').first);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Основной'), findsOneWidget);
    expect(find.textContaining('Тверская, 12, кв. 45'), findsOneWidget);

    await tester.tap(find.text('Профиль').first);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Имя и фамилия'),
      'Мария Иванова',
    );
    await tester.tap(find.text('Сохранить изменения'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(c.read(customerSessionProvider).value!.fullName, 'Мария Иванова');
  });

  for (final w in [360.0, 768.0]) {
    testWidgets('phone/tablet ${w.toInt()}: section list, no overflow', (
      tester,
    ) async {
      await pumpProfile(tester, Size(w, 900));
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(5));
      await tester.tap(find.text('Мои заказы'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Заказ 261019-7KQ2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
