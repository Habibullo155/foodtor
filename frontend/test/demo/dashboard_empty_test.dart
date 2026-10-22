import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/core/theme/app_theme.dart';
import 'package:saasshop/features/admin/data/admin_data.dart';
import 'package:saasshop/features/admin/data/admin_repository.dart';
import 'package:saasshop/features/admin/pages/dashboard_page.dart';

/// Свежий магазин: заказов ещё нет, за все дни выручка 0.
class _EmptyShop extends DemoAdminRepository {
  _EmptyShop({this.loaded = true});
  final bool loaded; // false — данные финансов ещё не пришли с сервера (пустой список дней)

  @override
  T? seed<T>() => switch (T) {
    const (FinanceData) when !loaded => FinanceData(const []) as T,
    const (FinanceData) => FinanceData([
      for (var i = 13; i >= 0; i--)
        DayFinance(DateTime.now().subtract(Duration(days: i)), 0, 0, 0),
    ]) as T,
    const (List<AdminOrder>) => const <AdminOrder>[] as T,
    _ => super.seed<T>(),
  };
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets(
    'dashboard before finance loaded (no days yet) and with zero revenue',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(_EmptyShop())],
          child: MaterialApp(
            theme: AppTheme.light(useGoogleFonts: false),
            home: const Scaffold(body: DashboardPage()),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Выручка и прибыль'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dashboard while finance is still loading', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(_EmptyShop(loaded: false)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(useGoogleFonts: false),
          home: const Scaffold(body: DashboardPage()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
