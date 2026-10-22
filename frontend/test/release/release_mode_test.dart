// Запуск: flutter test test/release   (без --dart-define — режим release по умолчанию)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/core/config/app_config.dart';
import 'package:saasshop/core/network/api_client.dart';
import 'package:saasshop/core/theme/app_theme.dart';
import 'package:saasshop/features/admin/admin_shell.dart';
import 'package:saasshop/features/admin/auth/admin_auth.dart';
import 'package:saasshop/features/admin/data/admin_data.dart';
import 'package:saasshop/features/admin/rbac.dart';
import 'package:saasshop/features/catalog/domain/catalog_meta.dart';
import 'package:saasshop/features/catalog/presentation/providers/catalog_filter.dart';
import 'package:saasshop/features/home/presentation/home_screen.dart';

import 'fake_api.dart';

ProviderContainer containerWith(FakeApi api) {
  final c = ProviderContainer();
  c.read(dioProvider).httpClientAdapter = api;
  addTearDown(c.dispose);
  return c;
}

/// Даёт завершиться реальным асинхронным запросам (Dio) и перерисовывает дерево.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pump(
  WidgetTester tester,
  ProviderContainer c,
  Widget home, {
  Size size = const Size(1440, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(useGoogleFonts: false),
        home: home,
      ),
    ),
  );
  await settle(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test(
    'built in release mode by default',
    () => expect(AppConfig.isDemo, isFalse),
  );

  test('API error messages are translated for users', () {
    final e = ApiException.from(
      DioExceptionShim.withDetail(401, 'Invalid email or password'),
    );
    expect(e.message, 'Неверный email или пароль');
  });

  testWidgets('empty store shows "coming soon" and hides stories/categories', (
    tester,
  ) async {
    final api = FakeApi({
      'GET /api/v1/categories': (_) => <Object>[],
      'GET /api/v1/products': (_) => {
        'items': <Object>[],
        'total': 0,
        'audience': 'anonymous',
      },
    });
    await pump(tester, containerWith(api), const HomeScreen());
    expect(find.text('Скоро открытие'), findsOneWidget);
    expect(find.text('Категории'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog from API: products, badges, categories', (tester) async {
    final api = FakeApi({
      'GET /api/v1/categories': (_) => [
        {
          'id': 1,
          'name': 'Овощи',
          'slug': 'veg',
          'parent_id': null,
          'image_url': null,
          'products_count': 2,
        },
      ],
      'GET /api/v1/products': (_) => {
        'items': [
          product(1, 'Томаты', '249.00', badges: ['hit']),
          product(2, 'Укроп', '59.00', badges: ['lowStock'], stockLeft: 3),
        ],
        'total': 2,
        'audience': 'anonymous',
      },
    });
    final c = containerWith(api);
    await pump(tester, c, const HomeScreen());
    expect(find.text('Томаты'), findsOneWidget);
    expect(find.text('Хит'), findsOneWidget);
    expect(find.text('Осталось 3 шт.'), findsOneWidget);
    expect(
      c.read(categoriesProvider).single,
      isA<Category>().having((x) => x.name, 'name', 'Овощи'),
    );
    expect(c.read(allProductsProvider).first.specs['Страна'], 'Россия');
  });

  testWidgets('catalog error offers retry', (tester) async {
    var fail = true;
    final api = FakeApi({
      'GET /api/v1/categories': (_) =>
          fail ? (500, {'detail': 'boom'}) : <Object>[],
      'GET /api/v1/products': (_) => {
        'items': [product(1, 'Томаты', '249.00')],
        'total': 1,
        'audience': 'anonymous',
      },
    });
    await pump(tester, containerWith(api), const HomeScreen());
    expect(find.text('Не удалось загрузить каталог'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Повторить'));
    await settle(tester);
    expect(find.text('Томаты'), findsOneWidget);
  });

  group('admin over API', () {
    Map<String, Handler> staffRoutes(
      String role,
      List<String> perms, {
      bool isStaff = true,
    }) => {
      'POST /api/v1/auth/login': (_) => {
        'access_token': 'a',
        'refresh_token': 'r',
        'token_type': 'bearer',
      },
      'GET /api/v1/auth/me': (_) => {
        'id': 1,
        'email': '$role@shop.ru',
        'full_name': 'Игорь Петров',
        'phone': null,
        'account_type': 'b2c',
        'b2b': null,
        'is_staff': isStaff,
        'role': role,
        'role_title': 'Сборщик заказов',
        'permissions': perms,
      },
      'GET /api/v1/staff/picking': (_) => [
        {
          'id': 5,
          'number': '261019-ABC',
          'status': 'new',
          'customer_note': 'Позвонить',
          'created_at': '2026-10-19T10:00:00+00:00',
          'items': [
            {
              'sku': 'S1',
              'name': 'Томаты',
              'quantity': 2,
              'unit': '1 кг',
              'image_url': null,
            },
          ],
        },
      ],
      'PATCH /api/v1/staff/orders/5/status': (_) => {
        'id': 5,
        'status': 'picking',
      },
    };

    testWidgets('picker logs in, sees only picking queue from /staff/picking', (
      tester,
    ) async {
      final api = FakeApi(staffRoutes('picker', ['orders:pick']));
      final c = containerWith(api);
      await pump(tester, c, const AdminRoot(), size: const Size(390, 844));
      expect(
        await tester.runAsync(
          () => c.read(adminAuthProvider.notifier).login('picker@shop.ru', 'x'),
        ),
        isA<LoginOk>(),
      );
      await settle(tester);
      expect(c.read(visibleSectionsProvider), [AdminSection.picking]);
      expect(c.read(adminOrdersProvider).single.number, '261019-ABC');
      expect(api.calls, isNot(contains('GET /api/v1/admin/orders')));
      expect(find.text('Томаты'), findsOneWidget);

      await tester.tap(find.text('Взять в сборку'));
      await settle(tester);
      expect(api.calls, contains('PATCH /api/v1/staff/orders/5/status'));
      expect(c.read(adminOrdersProvider).single.stage, OrderStage.picking);
      expect(tester.takeException(), isNull);
    });

    testWidgets('customer account cannot enter the admin panel', (
      tester,
    ) async {
      final api = FakeApi({
        ...staffRoutes('customer', [], isStaff: false),
        'POST /api/v1/auth/logout': (_) => null,
      });
      final c = containerWith(api);
      await pump(tester, c, const AdminRoot());
      final r = await tester.runAsync(
        () => c.read(adminAuthProvider.notifier).login('buyer@shop.ru', 'x'),
      ) as LoginFailed;
      expect(r.message, contains('не является сотрудником'));
      expect(c.read(adminAuthProvider), isNull);
    });

    testWidgets('failed status change rolls back and reports error', (
      tester,
    ) async {
      final routes = staffRoutes('picker', ['orders:pick'])
        ..['PATCH /api/v1/staff/orders/5/status'] = (_) =>
            (409, {'detail': 'Order is not paid yet'});
      final c = containerWith(FakeApi(routes));
      await pump(tester, c, const AdminRoot());
      await tester.runAsync(
        () => c.read(adminAuthProvider.notifier).login('picker@shop.ru', 'x'),
      );
      await settle(tester);
      await tester.runAsync(
        () => c
            .read(adminOrdersProvider.notifier)
            .setStage(5, OrderStage.picking),
      );
      expect(c.read(adminOrdersProvider).single.stage, OrderStage.newOrder);
      expect(c.read(adminErrorProvider), 'Order is not paid yet');
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
