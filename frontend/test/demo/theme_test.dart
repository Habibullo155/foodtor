import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/core/theme/app_theme.dart';
import 'package:saasshop/core/theme/theme_mode.dart';
import 'package:saasshop/features/account/account.dart';
import 'package:saasshop/features/admin/admin_shell.dart';
import 'package:saasshop/features/cart/presentation/cart_screen.dart';
import 'package:saasshop/features/catalog/data/catalog_repository.dart';
import 'package:saasshop/features/catalog/presentation/providers/shop_providers.dart';
import 'package:saasshop/features/home/presentation/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> pumpDark(
  WidgetTester tester,
  Widget home,
  Size size, {
  void Function(ProviderContainer)? setup,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = ProviderContainer();
  addTearDown(c.dispose);
  setup?.call(c);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(useGoogleFonts: false),
        darkTheme: AppTheme.dark(useGoogleFonts: false),
        themeMode: ThemeMode.dark,
        home: home,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return c;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('theme choice is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    expect(c.read(themeModeProvider), ThemeMode.system);
    c.read(themeModeProvider.notifier).set(ThemeMode.dark);
    c.dispose();
    // «Перезапуск» приложения: новый контейнер читает сохранённое значение
    c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    expect(c.read(themeModeProvider), ThemeMode.dark);
    c.dispose();
  });

  test('dark palette really is dark', () {
    final t = AppTheme.dark(useGoogleFonts: false);
    final p = t.extension<AppPalette>()!;
    expect(t.brightness, Brightness.dark);
    expect(p.background.computeLuminance(), lessThan(0.05));
    expect(p.textPrimary.computeLuminance(), greaterThan(0.8));
  });

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('home renders in dark at ${size.width.toInt()}', (
      tester,
    ) async {
      await pumpDark(tester, const HomeScreen(), size);
      expect(tester.takeException(), isNull);
      final bg = Theme.of(tester.element(find.byType(HomeScreen)))
          .scaffoldBackgroundColor;
      expect(bg, AppPalette.dark.background);
    });

    testWidgets('cart renders in dark at ${size.width.toInt()}', (
      tester,
    ) async {
      await pumpDark(
        tester,
        const Scaffold(body: CartScreen()),
        size,
        setup: (c) {
          for (final p in DemoCatalogRepository(Account.guest).all.take(3)) {
            c.read(cartProvider.notifier).add(p);
          }
        },
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admin login renders in dark with theme switch', (tester) async {
    await pumpDark(tester, const AdminRoot(), const Size(1440, 900));
    expect(find.byType(ThemeModeButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
