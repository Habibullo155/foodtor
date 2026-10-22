import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../presentation/cart_checkout.dart';

@immutable
class ServerQuote {
  const ServerQuote({
    required this.subtotal,
    required this.loyaltyDiscount,
    required this.promoDiscount,
    required this.deliveryFee,
    required this.total,
    this.promoError,
    this.tierName,
  });

  final double subtotal;
  final double loyaltyDiscount;
  final double promoDiscount;
  final double deliveryFee;
  final double total;
  final String? promoError;
  final String? tierName;

  static double _d(Object? v) => double.parse(v.toString());

  factory ServerQuote.fromJson(Map<String, dynamic> j) => ServerQuote(
    subtotal: _d(j['subtotal']),
    loyaltyDiscount: _d(j['loyalty_discount']),
    promoDiscount: _d(j['promo_discount']),
    deliveryFee: _d(j['delivery_fee']),
    total: _d(j['total']),
    promoError: j['promo_error'] as String?,
    tierName: j['tier_name'] as String?,
  );
}

@immutable
class PlacedOrder {
  const PlacedOrder(this.id, this.number, this.total, this.payUrl);
  final int id;
  final String number;
  final double total;
  final String? payUrl;
}

enum PaymentChoice { cash, cardOnline }

class CheckoutApi {
  CheckoutApi(this._ref);
  final Ref _ref;

  static String _delivery(DeliveryChoice d) => switch (d) {
    DeliveryChoice.express => 'express',
    DeliveryChoice.courier => 'courier',
    DeliveryChoice.pickup => 'pickup',
  };

  List<Map<String, int>> _items(Map<int, int> lines) => [
    for (final MapEntry(:key, :value) in lines.entries)
      {'product_id': key, 'quantity': value},
  ];

  Future<ServerQuote> quote(
    Map<int, int> lines,
    DeliveryChoice delivery,
    String? promo,
  ) async {
    try {
      final r = await _ref
          .read(dioProvider)
          .post<Map<String, dynamic>>(
            '/api/v1/me/orders/quote',
            data: {
              'items': _items(lines),
              'delivery': _delivery(delivery),
              'promo_code': promo,
            },
          );
      return ServerQuote.fromJson(r.data!);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<PlacedOrder> place({
    required Map<int, int> lines,
    required DeliveryChoice delivery,
    required String name,
    required String phone,
    required String address,
    required PaymentChoice payment,
    String? note,
    String? promo,
    double? lat,
    double? lng,
  }) async {
    try {
      final r = await _ref
          .read(dioProvider)
          .post<Map<String, dynamic>>(
            '/api/v1/me/orders',
            data: {
              'items': _items(lines),
              'delivery': _delivery(delivery),
              'name': name,
              'phone': phone,
              'address': address,
              'payment': payment == PaymentChoice.cash ? 'cash' : 'card_online',
              'note': note,
              'promo_code': promo,
              'lat': ?lat,
              'lng': ?lng,
            },
          );
      final j = r.data!;
      return PlacedOrder(
        j['id'] as int,
        j['number'] as String,
        double.parse(j['total'].toString()),
        j['pay_url'] as String?,
      );
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final checkoutApiProvider = Provider<CheckoutApi>(
  (ref) => AppConfig.isDemo ? DemoCheckoutApi(ref) : CheckoutApi(ref),
);

/// Демо: та же форма оформления, но итог считает корзина, а заказ «создаётся» локально.
class DemoCheckoutApi extends CheckoutApi {
  DemoCheckoutApi(super.ref);

  @override
  Future<ServerQuote> quote(
    Map<int, int> lines,
    DeliveryChoice delivery,
    String? promo,
  ) async {
    final t = _ref.read(cartTotalsProvider);
    return ServerQuote(
      subtotal: t.itemsFull,
      loyaltyDiscount: t.discount,
      promoDiscount: t.promoDiscount,
      deliveryFee: t.delivery,
      total: t.total,
    );
  }

  @override
  Future<PlacedOrder> place({
    required Map<int, int> lines,
    required DeliveryChoice delivery,
    required String name,
    required String phone,
    required String address,
    required PaymentChoice payment,
    String? note,
    String? promo,
    double? lat,
    double? lng,
  }) async {
    final total = _ref.read(cartTotalsProvider).total;
    final n = (DateTime.now().millisecondsSinceEpoch % 100000).toString();
    return PlacedOrder(0, n.padLeft(5, '0'), total, null);
  }
}
