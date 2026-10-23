import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/features/admin/data/admin_data.dart';
import 'package:saasshop/features/admin/data/admin_repository.dart';
import 'package:saasshop/features/admin/rbac.dart';

import 'admin_test.dart' show login, pumpAdmin;
import 'stories_admin_test.dart' show settle;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('business clients: approve application, set minimum order', (
    tester,
  ) async {
    final c = await pumpAdmin(tester, const Size(1440, 1000));
    await login(tester, c, 'owner@saasshop.local');
    expect(c.read(visibleSectionsProvider), contains(AdminSection.business));
    await tester.tap(find.text('Бизнес-клиенты').first);
    await settle(tester);
    expect(find.text('ИП Соколова Е. А.'), findsOneWidget);
    expect(find.text('Условия для оптовиков'), findsOneWidget);

    await tester.tap(find.text('Подтвердить').first);
    await settle(tester);
    expect(find.text('Подтвердить «ИП Соколова Е. А.»?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Подтвердить').last);
    await settle(tester);
    final sokolova = c
        .read(companiesProvider)
        .firstWhere((x) => x.taxId == '771234567859');
    expect(sokolova.status, B2BStatus.approved);

    await tester.enterText(
      find.widgetWithText(TextField, 'Минимальный заказ'),
      '7000',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await settle(tester);
    final min = await tester.runAsync(
      () => c.read(adminRepositoryProvider).wholesaleMinOrder(),
    );
    expect(min, 7000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product editor has wholesale price', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 1000));
    await login(tester, c, 'manager@saasshop.local');
    expect(c.read(visibleSectionsProvider), contains(AdminSection.business));
    final p = c.read(adminProductsProvider).first;
    expect(p.wholesalePrice, isNotNull);
    expect(p.toJson()['wholesale_price'], p.wholesalePrice!.toStringAsFixed(2));
    await tester.tap(find.text('Товары').first);
    await settle(tester);
    await tester.tap(find.text(p.name).first);
    await settle(tester);
    expect(find.text('Оптовая цена, ₽'), findsOneWidget);
    expect(find.textContaining('Скидка для оптовиков'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('work hours: default Mon–Sat 10–22, saved text', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 4000));
    await login(tester, c, 'owner@saasshop.local');
    await tester.tap(find.text('Магазин и доставка').first);
    await settle(tester);
    expect(find.text('Часы работы'), findsOneWidget);
    expect(find.text('с 10:00'), findsOneWidget);
    expect(find.text('до 22:00'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Вс'));
    await tester.pump();
    await tester.tap(find.text('Сохранить часы'));
    await settle(tester);
    final saved = await tester.runAsync(
      () => c.read(adminRepositoryProvider).workHours(),
    );
    expect(saved!.text, 'ежедневно с 10:00 до 22:00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('socials: accepts @name, rejects foreign links', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 4400));
    await login(tester, c, 'owner@saasshop.local');
    await tester.tap(find.text('Магазин и доставка').first);
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Telegram'),
      '@foodtor_shop',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Instagram'),
      'https://www.instagram.com/foodtor/',
    );
    await tester.pump();
    await tester.tap(find.text('Сохранить соцсети'));
    await settle(tester);
    final saved = await tester.runAsync(
      () => c.read(adminRepositoryProvider).socials(),
    );
    expect(saved!.telegram, 'https://t.me/foodtor_shop');
    expect(saved.instagram, 'https://instagram.com/foodtor');
    await expectLater(
      c
          .read(adminRepositoryProvider)
          .saveSocials(const ShopSocials(telegram: 'https://evil.ru/x')),
      throwsA(isA<Object>()),
    );
    expect(tester.takeException(), isNull);
  });
}
