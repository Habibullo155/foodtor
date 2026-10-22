import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';

import '../../catalog/domain/product.dart';
import '../../catalog/presentation/providers/catalog_filter.dart';
import '../../catalog/presentation/providers/shop_providers.dart';

/// Правила доставки продуктового магазина (в проде — из настроек бэкенда).
abstract final class DeliveryRules {
  static const freeCourierFrom = 1500.0;
  static const courierFee = 199.0;
  static const expressFee = 149.0;
}

enum DeliveryChoice {
  express('Экспресс', '2 часа', Icons.bolt_rounded),
  courier('Курьер', 'Сегодня 18–22', Icons.local_shipping_outlined),
  pickup('Самовывоз', 'Через 1 час', Icons.storefront_outlined);

  const DeliveryChoice(this.label, this.eta, this.icon);
  final String label;
  final String eta;
  final IconData icon;

  double feeFor(double goods) => switch (this) {
    express => DeliveryRules.expressFee,
    courier =>
      goods >= DeliveryRules.freeCourierFrom ? 0 : DeliveryRules.courierFee,
    pickup => 0,
  };
}

class DeliveryChoiceNotifier extends Notifier<DeliveryChoice> {
  @override
  DeliveryChoice build() => DeliveryChoice.courier;
  void set(DeliveryChoice v) => state = v;
}

final deliveryChoiceProvider =
    NotifierProvider<DeliveryChoiceNotifier, DeliveryChoice>(
      DeliveryChoiceNotifier.new,
    );

/// Промокоды (демо). В проде — POST /me/cart/promo, проверка на сервере.
@immutable
class Promo {
  const Promo(this.code, this.amount, this.minOrder);
  final String code;
  final double amount;
  final double minOrder;
}

const _demoPromos = {'FRESH300': Promo('FRESH300', 300, 1500)};

class PromoNotifier extends Notifier<Promo?> {
  @override
  Promo? build() => null;

  /// Возвращает текст ошибки или null при успехе.
  String? apply(String raw) {
    final code = raw.trim().toUpperCase();
    if (code.isEmpty) return 'Введите промокод';
    if (!AppConfig.isDemo) {
      // Релиз: код проверит сервер при оформлении (сумма скидки и условия — только там)
      state = Promo(code, 0, 0);
      return null;
    }
    final promo = _demoPromos[code];
    if (promo == null) return 'Промокод не найден';
    state = promo;
    return null;
  }

  void clear() => state = null;
}

final promoProvider = NotifierProvider<PromoNotifier, Promo?>(
  PromoNotifier.new,
);

/// Все суммы корзины в одном месте — их читают и сводка, и нижняя панель, и прогресс доставки.
@immutable
class CartTotals {
  const CartTotals({
    required this.count,
    required this.itemsFull,
    required this.goods,
    required this.promoDiscount,
    required this.promoShortfall,
    required this.delivery,
    required this.isWholesale,
  });

  final int count;
  final double itemsFull; // по «старым»/розничным ценам
  final double goods; // по фактическим ценам
  final double promoDiscount;
  final double?
  promoShortfall; // сколько не хватает до минимальной суммы промокода
  final double delivery;
  final bool isWholesale;

  double get discount => itemsFull - goods;
  double get total => goods - promoDiscount + delivery;
  double get toFreeDelivery =>
      (DeliveryRules.freeCourierFrom - goods).clamp(0, double.infinity);
  double get freeDeliveryProgress =>
      (goods / DeliveryRules.freeCourierFrom).clamp(0, 1);
}

final cartTotalsProvider = Provider<CartTotals>((ref) {
  final entries = ref.watch(cartProvider).values;
  final delivery = ref.watch(deliveryChoiceProvider);
  final promo = ref.watch(promoProvider);

  var full = 0.0, goods = 0.0, count = 0;
  var wholesale = false;
  for (final e in entries) {
    final p = e.product.priceInfo;
    final strike = p.isWholesale
        ? p.retailPrice
        : (p.compareAtPrice ?? p.price);
    full += strike * e.quantity;
    goods += e.lineTotal;
    count += e.quantity;
    wholesale |= p.isWholesale;
  }
  final promoOk = promo != null && goods >= promo.minOrder;
  return CartTotals(
    count: count,
    itemsFull: full,
    goods: goods,
    promoDiscount: promoOk ? promo.amount : 0,
    promoShortfall: promo != null && !promoOk ? promo.minOrder - goods : null,
    delivery: delivery.feeFor(goods),
    isWholesale: wholesale,
  );
});

/// «Не забудьте купить»: то, что чаще всего забывают — зелень, лимоны, соль, масло, хлебные позиции.
/// Без товаров, которые уже в корзине. В проде — персонально по истории заказов пользователя.
const _staples = [35, 36, 20, 57, 54, 69, 45, 17, 8, 42];

final forgottenItemsProvider = Provider<List<Product>>((ref) {
  final inCart = ref.watch(cartProvider.select((c) => c.keys.toSet()));
  // Не дублируем то, что уже предложено в «С этим часто покупают»
  final crossSell = {
    for (final p
        in ref.watch(cartRecommendationsProvider).value ?? const <Product>[])
      p.id,
  };
  final byId = {for (final p in ref.watch(allProductsProvider)) p.id: p};
  return [
    for (final id in _staples)
      if (!inCart.contains(id) && !crossSell.contains(id) && byId[id] != null)
        byId[id]!,
  ].take(6).toList();
});
