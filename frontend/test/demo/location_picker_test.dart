import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saasshop/core/delivery/delivery_check.dart';
import 'package:saasshop/core/delivery/location_picker.dart';
import 'package:saasshop/core/theme/app_theme.dart';

void main() {
  setUp(() {
    DemoDeliveryChecker.radiusKm = 20;
    DemoDeliveryChecker.enabled = true;
  });

  Future<PickedLocation?> pick(
    WidgetTester tester, {
    double? lat,
    double? lng,
  }) async {
    PickedLocation? result;
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(useGoogleFonts: false),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async => result = await showLocationPicker(
                    context,
                    lat: lat,
                    lng: lng,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    return result;
  }

  testWidgets('point in Moscow: address + "доставляем", returns the point', (
    tester,
  ) async {
    await pick(tester, lat: 55.7600, lng: 37.6200);
    expect(find.text('Куда доставить'), findsOneWidget);
    expect(find.text('Моё местоположение'), findsOneWidget);
    expect(find.textContaining('Москва, точка на карте'), findsOneWidget);
    expect(find.textContaining('Сюда доставляем'), findsOneWidget);
    await tester.tap(find.text('Доставить сюда'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Куда доставить'), findsNothing);
  });

  testWidgets('point in Tula: "мы не доставляем", button disabled', (
    tester,
  ) async {
    await pick(tester, lat: 54.1931, lng: 37.6177);
    expect(
      find.textContaining('Мы не доставляем по вашему адресу'),
      findsOneWidget,
    );
    expect(find.text('Сюда не доставляем'), findsOneWidget);
    final btn = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Сюда не доставляем'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(btn.onPressed, isNull);
  });
}
