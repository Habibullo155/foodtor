import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saasshop/features/account/account.dart';
import 'package:saasshop/features/cart/presentation/cart_checkout.dart';
import 'package:saasshop/features/cart/presentation/cart_screen.dart';
import 'package:saasshop/features/catalog/data/catalog_repository.dart';
import 'package:saasshop/features/catalog/presentation/providers/shop_providers.dart';

void main() {
  testWidgets(
    'cart shows cross-sell, quick-add moves item into cart and out of the rail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final phone = DemoCatalogRepository(Account.guest)
          .all
          .first; // Томаты розовые
      container.read(cartProvider.notifier).add(phone);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CartScreen())),
        ),
      );
      await tester.pump(
        const Duration(milliseconds: 500),
      ); // ответ демо-репозитория
      await tester.pumpAndSettle();

      expect(find.text('С этим часто покупают'), findsOneWidget);
      expect(find.textContaining('Огурцы'), findsOneWidget);
      expect(find.textContaining('+189'), findsOneWidget); // цена-приращение

      await tester.tap(find.byTooltip('Добавить в корзину').first);
      await tester.pump();
      expect(container.read(cartProvider).length, 2);
      expect(find.text('Отменить'), findsOneWidget); // undo-снэкбар

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      final recs = container.read(cartRecommendationsProvider).value!;
      expect(
        recs.map((p) => p.id),
        isNot(contains(2)),
        reason: 'товар из корзины не рекомендуется',
      );
    },
  );

  test('B2B approval reprices the cart without clearing it', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final phone = DemoCatalogRepository(Account.guest).all.first;
    container.read(cartProvider.notifier).add(phone, 2);
    expect(
      container.read(cartProvider)[1]!.product.priceInfo.isWholesale,
      isFalse,
    );

    container
        .read(accountProvider.notifier)
        .set(
          const Account(type: AccountType.b2b, b2bStatus: B2BStatus.approved),
        );
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final entry = container.read(cartProvider)[1]!;
    expect(entry.quantity, 2);
    expect(entry.product.priceInfo.isWholesale, isTrue);
    expect(entry.product.price, lessThan(phone.price));
  });

  test('free-delivery threshold, courier fee and promo minimum', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final tomato = DemoCatalogRepository(Account.guest).all.first; // 249 ₽
    c.read(cartProvider.notifier).add(tomato, 2); // 498 ₽
    var t = c.read(cartTotalsProvider);
    expect(t.delivery, DeliveryRules.courierFee);
    expect(t.toFreeDelivery, 1500 - 498);

    expect(c.read(promoProvider.notifier).apply('nope'), isNotNull);
    expect(c.read(promoProvider.notifier).apply(' fresh300 '), isNull);
    t = c.read(cartTotalsProvider);
    expect(
      (t.promoDiscount, t.promoShortfall),
      (0, 1500 - 498),
    ); // промокод ждёт минимальную сумму

    c.read(cartProvider.notifier).add(tomato, 5); // 7 × 249 = 1743 ₽
    t = c.read(cartTotalsProvider);
    expect((t.delivery, t.promoDiscount, t.total), (0, 300, 1743 - 300));
  });

  testWidgets('cart has no overflow from phone to desktop', (tester) async {
    for (final w in [320.0, 390.0, 900.0, 1400.0]) {
      await tester.binding.setSurfaceSize(Size(w, 900));
      final c = ProviderContainer();
      for (final p in DemoCatalogRepository(Account.guest).all.take(4)) {
        c.read(cartProvider.notifier).add(p);
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: Scaffold(body: CartScreen())),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: 'width $w');
      expect(find.textContaining('курьер привезёт бесплатно'), findsOneWidget);
      // Блок ниже первого экрана: прокручиваем ленту корзины вниз
      await tester.scrollUntilVisible(
        find.text('Не забудьте купить'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Не забудьте купить'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width $w after scroll');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
    await tester.binding.setSurfaceSize(null);
  });
}
