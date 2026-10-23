import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/features/admin/data/admin_data.dart';
import 'package:saasshop/features/admin/rbac.dart';

import 'admin_test.dart' show login, pumpAdmin;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('category url for story buttons matches the site slug', () {
    expect(
      const AdminCategory(1, 'Крупы и бобовые').url,
      '/catalog/krupy-i-bobovye',
    );
    expect(
      const AdminCategory(1, 'Ягоды', savedSlug: 'yagody').url,
      '/catalog/yagody',
    );
  });

  testWidgets('stories: list, reorder, hide, edit, delete', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 1000));
    await login(tester, c, 'owner@saasshop.local');
    expect(c.read(visibleSectionsProvider), contains(AdminSection.stories));
    await tester.tap(find.text('Истории').first);
    await settle(tester);
    expect(find.text('Так это выглядит на сайте'), findsOneWidget);
    expect(find.text('Новая история'), findsOneWidget);

    final n = c.read(storiesProvider.notifier);
    final first = c.read(storiesProvider).first;
    await tester.runAsync(() => n.move(first, 1));
    expect(c.read(storiesProvider)[1].id, first.id);

    await tester.runAsync(() => n.toggle(first));
    expect(
      c.read(storiesProvider).firstWhere((s) => s.id == first.id).isActive,
      isFalse,
    );

    await tester.tap(find.byTooltip('Изменить').first);
    await settle(tester);
    expect(find.text('Подпись под кружком'), findsOneWidget);
    expect(find.text('Добавить слайд'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await settle(tester);

    final before = c.read(storiesProvider).length;
    await tester.runAsync(() => n.delete(first));
    expect(c.read(storiesProvider).length, before - 1);
    expect(tester.takeException(), isNull);
  });
}
