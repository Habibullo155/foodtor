import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import 'catalog_meta.dart';

@immutable
class WholesaleTier {
  const WholesaleTier(this.minQuantity, this.unitPrice);
  final int minQuantity;
  final double unitPrice;
}

/// Цена, уже рассчитанная бэкендом ДЛЯ ТЕКУЩЕГО пользователя (аноним / B2C / B2B).
/// Клиент цены не вычисляет — только отображает. Это исключает расхождение
/// «в приложении одна цена, в заказе другая» и не раскрывает правила прайс-листов.
@immutable
class PriceInfo {
  const PriceInfo({
    required this.price,
    required this.retailPrice,
    this.compareAtPrice,
    this.isWholesale = false,
    this.tiers = const [],
  });

  final double price;
  final double retailPrice;
  final double? compareAtPrice; // что зачеркнуть
  final bool isWholesale;
  final List<WholesaleTier> tiers;

  int? get discountPercent {
    final old = compareAtPrice;
    if (old == null || old <= price) return null;
    return ((1 - price / old) * 100).round();
  }

  /// Цена за штуку при заданном объёме — только для *предварительного* отображения
  /// по лестнице, присланной сервером. Итог корзины всегда из /me/cart/quote.
  double unitPriceFor(int quantity) {
    var result = price;
    for (final t in tiers) {
      if (quantity >= t.minQuantity) result = t.unitPrice;
    }
    return result;
  }

  /// Следующая ступень опта — для подсказки «добавьте ещё N шт, и цена станет X».
  WholesaleTier? nextTierAfter(int quantity) {
    for (final t in tiers) {
      if (t.minQuantity > quantity) return t;
    }
    return null;
  }

  factory PriceInfo.fromJson(Map<String, dynamic> j) => PriceInfo(
    price: _d(j['price'])!,
    retailPrice: _d(j['retail_price'])!,
    compareAtPrice: _d(j['compare_at_price']),
    isWholesale: j['is_wholesale'] as bool? ?? false,
    tiers: [
      for (final t
          in (j['tiers'] as List? ?? const []).cast<Map<String, dynamic>>())
        WholesaleTier(t['min_quantity'] as int, _d(t['unit_price'])!),
    ],
  );
}

/// Деньги приходят строками ("1290.00") — Decimal на бэкенде, без потерь float в JSON.
double? _d(Object? v) => v == null ? null : double.parse(v.toString());

@immutable
class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.priceInfo,
    this.description = '',
    this.imageUrls = const [],
    this.rating,
    this.reviewsCount = 0,
    this.inStock = true,
    this.brand,
    this.unit,
    this.categoryId,
    this.badges = const {},
    this.stockLeft,
    this.delivery = const [],
    this.specs = const {},
  });

  final int id;
  final String sku;
  final String name;
  final String? brand;
  final String? unit; // фасовка: «1 кг», «500 г», «пучок»
  final int? categoryId;
  final Set<ProductBadge>
  badges; // «Хит», «Новинка», «Осталось мало» — вычисляет бэкенд
  final int? stockLeft; // показывается только при малом остатке
  final List<DeliveryOption> delivery;
  final Map<String, String>
  specs; // характеристики для фильтров: {'Страна': 'Россия'}
  final String description;
  final PriceInfo priceInfo;
  final List<String> imageUrls;
  final double? rating;
  final int reviewsCount;
  final bool inStock;

  double get price => priceInfo.price;
  double? get compareAtPrice => priceInfo.compareAtPrice;
  int? get discountPercent => priceInfo.discountPercent;

  /// Самый быстрый вариант доставки — для короткой строки на карточке.
  DeliveryOption? get fastestDelivery => delivery.isEmpty
      ? null
      : (delivery.toList()..sort((a, b) => a.minDays.compareTo(b.minDays)))
            .first;

  /// Понимает и ProductSummaryOut, и ProductDetailOut.
  factory Product.fromJson(Map<String, dynamic> j) {
    final price = PriceInfo.fromJson(j['price'] as Map<String, dynamic>);
    final images = (j['images'] as List?)?.cast<String>() ?? const <String>[];
    return Product(
      id: j['id'] as int,
      sku: j['sku'] as String,
      name: j['name'] as String,
      description: j['description'] as String? ?? '',
      priceInfo: price,
      imageUrls: [
        ...images,
        if (images.isEmpty)
          if (j['image_url'] case final String url) url,
      ],
      inStock: j['in_stock'] as bool? ?? true,
      brand: j['brand'] as String?,
      unit: j['unit'] as String?,
      categoryId: j['category_id'] as int?,
      badges: {
        for (final b in (j['badges'] as List? ?? const []).cast<String>())
          ...ProductBadge.values.where((e) => e.name == b),
      },
      stockLeft: j['stock_left'] as int?,
      specs: {
        for (final MapEntry(:key, :value)
            in ((j['attributes'] as Map?) ?? const {}).entries)
          key.toString(): value.toString(),
      },
      rating: (j['rating'] as num?)?.toDouble(),
      reviewsCount: j['reviews_count'] as int? ?? 0,
      // Доставку API не отдаёт на каждый товар — правила общие для магазина
      delivery: defaultDelivery,
    );
  }
}

/// Стандартные варианты доставки магазина (итог всё равно пересчитывает сервер).
const defaultDelivery = [
  DeliveryOption(
    method: DeliveryMethod.express,
    minDays: 0,
    maxDays: 0,
    price: AppConfig.expressFee,
  ),
  DeliveryOption(
    method: DeliveryMethod.courier,
    minDays: 1,
    maxDays: 1,
    price: 0,
  ),
  DeliveryOption(
    method: DeliveryMethod.pickup,
    minDays: 0,
    maxDays: 0,
    price: 0,
  ),
];

@immutable
class ProductDetails {
  const ProductDetails({
    required this.product,
    this.crossSell = const [],
    this.upsell = const [],
  });
  final Product product;
  final List<Product> crossSell; // «С этим товаром часто покупают»
  final List<Product> upsell; // «Похожие товары»

  factory ProductDetails.fromJson(Map<String, dynamic> j) => ProductDetails(
    product: Product.fromJson(j),
    crossSell: [
      for (final p
          in (j['cross_sell_products'] as List).cast<Map<String, dynamic>>())
        Product.fromJson(p),
    ],
    upsell: [
      for (final p
          in (j['upsell_products'] as List).cast<Map<String, dynamic>>())
        Product.fromJson(p),
    ],
  );
}
