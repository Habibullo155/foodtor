import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/core/theme/app_theme.dart';
import 'package:saasshop/features/admin/auth/admin_auth.dart';
import 'package:saasshop/features/admin/data/admin_data.dart';
import 'package:saasshop/features/admin/data/admin_repository.dart';
import 'package:saasshop/features/admin/pages/delivery_page.dart';
import 'package:saasshop/features/admin/pages/marketing_page.dart';
import 'package:saasshop/features/admin/pages/support_page.dart';
import 'package:saasshop/features/admin/rbac.dart';

import 'admin_test.dart' show login, pumpAdmin;
import 'stories_admin_test.dart' show settle;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('delivery terms: minimum order, express off, saved', (
    tester,
  ) async {
    final c = await pumpAdmin(tester, const Size(1440, 3200));
    await login(tester, c, 'owner@saasshop.local');
    await tester.tap(find.text('Магазин и доставка').first);
    await settle(tester);
    expect(find.text('Условия доставки'), findsOneWidget);
    expect(find.text('Контакты и реквизиты'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Минимальный заказ на доставку'),
      '3000',
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'Экспресс-доставка'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить').first);
    await settle(tester);
    final saved = await tester.runAsync(
      () => c.read(adminRepositoryProvider).shopSettings(),
    );
    expect(saved!.minOrder, 3000);
    expect(saved.expressEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('banners and referral program', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 1400));
    await login(tester, c, 'owner@saasshop.local');
    expect(c.read(visibleSectionsProvider), contains(AdminSection.marketing));
    await tester.tap(find.text('Баннеры и бонусы').first);
    await settle(tester);
    expect(find.text('Неделя ягод'), findsWidgets);
    expect(find.text('Приведи друга'), findsOneWidget);

    await tester.tap(find.text('Новый баннер'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Заголовок'),
      'Скидка на кофе',
    );
    await tester.tap(find.widgetWithText(ActionChip, 'Акции'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Кнопка'),
      'Смотреть',
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Сохранить'),
      ),
    );
    await settle(tester);
    expect(c.read(bannersProvider).last.linkUrl, '/promo');

    await tester.enterText(
      find.widgetWithText(TextField, 'Пригласившему'),
      '500',
    );
    await tester.pump();
    expect(find.textContaining('промокод на 500 ₽'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить').last);
    await settle(tester);
    final ref = await tester.runAsync(
      () => c.read(adminRepositoryProvider).referralSettings(),
    );
    expect(ref!.inviterAmount, 500);
    expect(tester.takeException(), isNull);
  });

  testWidgets('support inbox: unread badge, answer customer', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 1000));
    await login(tester, c, 'manager@saasshop.local');
    await tester.runAsync(
      () => c.read(supportThreadsProvider.notifier).reload(),
    );
    expect(c.read(supportUnreadProvider), 1);
    await tester.tap(find.text('Поддержка').first);
    await settle(tester);
    await tester.tap(find.text('Мария Кузнецова'));
    await settle(tester);
    expect(c.read(supportUnreadProvider), 0);
    await tester.enterText(
      find.widgetWithText(TextField, 'Ответ покупателю'),
      'Да, привезём до 22:00',
    );
    await tester.tap(find.text('Ответить'));
    await settle(tester);
    expect(find.text('Да, привезём до 22:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('categories get photos; profile name editable', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 1000));
    await login(tester, c, 'owner@saasshop.local');
    await tester.tap(find.text('Товары').first);
    await settle(tester);
    expect(find.text('Выгрузить в Excel'), findsOneWidget);
    await tester.tap(find.text('Категории'));
    await settle(tester);
    expect(find.text('Новая категория'), findsOneWidget);
    final cat = c.read(adminCategoriesProvider).first;
    await tester.runAsync(
      () => c
          .read(adminCategoriesProvider.notifier)
          .save(cat.copyWith(imageUrl: '/media/products/x.webp')),
    );
    expect(
      c.read(adminCategoriesProvider).first.imageUrl,
      '/media/products/x.webp',
    );
    await tester.tap(find.text('Готово'));
    await settle(tester);

    c
        .read(adminAuthProvider.notifier)
        .updateProfile(name: 'Хабиб З.', phone: '+79853947262');
    await tester.pump();
    expect(c.read(adminAuthProvider)!.name, 'Хабиб З.');
    expect(tester.takeException(), isNull);
  });

  for (final (name, page) in [
    ('marketing', const MarketingPage()),
    ('support', const SupportPage()),
    ('delivery settings', const DeliverySettingsPage()),
  ]) {
    testWidgets('$name fits a phone', (tester) async {
      final c = await pumpAdmin(tester, const Size(390, 844));
      await login(tester, c, 'owner@saasshop.local');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light(useGoogleFonts: false),
            home: Scaffold(body: page),
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
