import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saasshop/core/theme/app_theme.dart';
import 'package:saasshop/features/catalog/presentation/providers/catalog_filter.dart';
import 'package:saasshop/features/catalog/presentation/widgets/product_card.dart';
import 'package:saasshop/features/home/presentation/desktop_header.dart';
import 'package:saasshop/features/home/presentation/home_screen.dart';
import 'package:saasshop/features/stories/presentation/story_viewer.dart';

Future<ProviderContainer> pumpHome(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(useGoogleFonts: false),
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return container;
}

void main() {
  testWidgets('phone: bottom navigation, no desktop header, 2-column grid', (
    tester,
  ) async {
    await pumpHome(tester, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(DesktopHeader), findsNothing);
    final cards = find.byType(ProductCard);
    final dx = {
      for (final e in cards.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dx.round(),
    };
    expect(dx.length, 2);
  });

  testWidgets('desktop: top header with search + filter sidebar, 4-5 columns', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1600, 1000));
    expect(find.byType(DesktopHeader), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Фильтры'), findsOneWidget);
    expect(find.text('Бренд'), findsOneWidget);
    final cards = find.byType(ProductCard);
    final dx = {
      for (final e in cards.evaluate())
        tester.getTopLeft(find.byWidget(e.widget)).dx.round(),
    };
    expect(dx.length, inInclusiveRange(4, 5));
  });

  testWidgets('category tile filters the grid; tapping again resets', (
    tester,
  ) async {
    final c = await pumpHome(tester, const Size(390, 844));
    final all = c.read(filteredProductsProvider).length;
    await tester.tap(find.text('Ягоды'));
    await tester.pump();
    expect(c.read(filteredProductsProvider).length, 6);
    await tester.tap(find.text('Ягоды'));
    await tester.pump();
    expect(c.read(filteredProductsProvider).length, all);
  });

  testWidgets(
    'story opens full-screen viewer, CTA applies category and closes',
    (tester) async {
      final c = await pumpHome(tester, const Size(390, 844));
      await tester.tap(find.text('Фермерское'));
      await tester
          .pump(); // кадр 1: маршрут строится offstage (подготовка Hero)
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryViewer), findsOneWidget);
      await tester.tap(find.text('К овощам'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryViewer), findsNothing);
      expect(c.read(catalogFilterProvider).categoryId, 1);
    },
  );

  for (final width in [320.0, 600.0, 1024.0, 1280.0, 2560.0]) {
    testWidgets('no layout overflow at ${width.toInt()}px', (tester) async {
      await pumpHome(tester, Size(width, 1000));
      expect(tester.takeException(), isNull);
    });
  }
}
