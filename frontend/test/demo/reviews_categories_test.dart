import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/features/admin/data/admin_data.dart';
import 'package:saasshop/features/catalog/presentation/providers/catalog_filter.dart';

import 'admin_test.dart' show login, pumpAdmin;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets(
    'reviews: filter by rating, bulk-approve high ratings, reject selected',
    (tester) async {
      final c = await pumpAdmin(tester, const Size(1440, 1000));
      await login(tester, c, 'owner@saasshop.local');
      await tester.tap(find.text('Отзывы').first);
      await settle(tester);

      List<AdminReview> pending() => c
          .read(reviewsProvider)
          .where((r) => r.state == ReviewState.pending)
          .toList();
      final highPending = pending().where((r) => r.rating >= 4).length;
      expect(highPending, greaterThan(0));
      expect(find.text('На модерации · ${pending().length}'), findsOneWidget);

      // «Опубликовать все с оценкой 4–5»
      await tester.tap(find.textContaining('Опубликовать все с оценкой 4–5'));
      await settle(tester);
      expect(pending().where((r) => r.rating >= 4), isEmpty);

      // фильтр «★ 1–2» → выбрать все → отклонить
      await tester.tap(find.text('★ 1–2'));
      await settle(tester);
      final lowCount = pending().where((r) => r.rating <= 2).length;
      expect(find.text('Показано: $lowCount'), findsOneWidget);
      await tester.tap(find.text('Выбрать все ($lowCount)'));
      await settle(tester);
      await tester.tap(find.text('Отклонить выбранные'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Отклонить'));
      await settle(tester);
      expect(pending().where((r) => r.rating <= 2), isEmpty);
      expect(pending().every((r) => r.rating == 3), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  test('categories collapse toggles and defaults to shown', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(categoriesCollapsedProvider), isFalse);
    c.read(categoriesCollapsedProvider.notifier).toggle();
    expect(c.read(categoriesCollapsedProvider), isTrue);
  });
}
