import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saasshop/core/responsive/responsive_layout.dart';
import 'package:saasshop/features/admin/rbac.dart';

void main() {
  test('window size classes', () {
    expect(ScreenSize.fromWidth(390), ScreenSize.compact);
    expect(ScreenSize.fromWidth(700), ScreenSize.medium);
    expect(ScreenSize.fromWidth(1280), ScreenSize.expanded);
  });

  testWidgets('ResponsiveLayout switches by available width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Future<void> pumpAt(double width) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            child: ResponsiveLayout(
              compact: (_) => const Text('phone'),
              expanded: (_) => const Text('desktop'),
            ),
          ),
        ),
      ),
    );
    await pumpAt(400);
    expect(find.text('phone'), findsOneWidget);
    await pumpAt(1000);
    await tester.pumpAndSettle();
    expect(find.text('desktop'), findsOneWidget);
  });

  test('picker sees only the picking section', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(permissionsProvider.notifier).set({Permission.ordersPick});
    expect(c.read(visibleSectionsProvider), [AdminSection.picking]);
  });
}
