import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

import '../../account/account.dart';
import '../domain/catalog_meta.dart';
import '../domain/recommender.dart';
import 'demo_catalog.dart';
import '../domain/product.dart';

/// Весь каталог разом: для продуктового магазина это сотни позиций — фильтры работают мгновенно на клиенте.
class CatalogSnapshot {
  const CatalogSnapshot(this.categories, this.products);
  final List<Category> categories;
  final List<Product> products;
}

abstract interface class CatalogRepository {
  Future<CatalogSnapshot> loadCatalog();

  Future<ProductDetails> getProduct(int id);

  /// Блок «С этим часто покупают» для корзины (исключает то, что уже в корзине).
  Future<List<Product>> getCartRecommendations(
    List<int> cartProductIds, {
    int limit = 8,
  });
}

/// Боевая реализация. Access-токен добавляет interceptor Dio, поэтому сервер сам
/// определяет аудиторию и возвращает персональные цены.
class ApiCatalogRepository implements CatalogRepository {
  ApiCatalogRepository(this._dio);
  final Dio _dio;

  @override
  Future<CatalogSnapshot> loadCatalog() async {
    try {
      final (cats, products) = await (
        _dio.get<List<dynamic>>('/api/v1/categories'),
        _dio.get<Map<String, dynamic>>(
          '/api/v1/products',
          queryParameters: {'limit': 500},
        ),
      ).wait;
      return CatalogSnapshot(
        [
          for (final (i, c) in cats.data!.cast<Map<String, dynamic>>().indexed)
            Category.fromJson(c, i),
        ],
        [
          for (final p
              in (products.data!['items'] as List).cast<Map<String, dynamic>>())
            Product.fromJson(p),
        ],
      );
    } catch (e) {
      throw ApiException.from(
        e is ParallelWaitError
            ? (e.errors as dynamic).$1 ?? (e.errors as dynamic).$2
            : e,
      );
    }
  }

  @override
  Future<ProductDetails> getProduct(int id) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/v1/products/$id');
      return ProductDetails.fromJson(r.data!);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  @override
  Future<List<Product>> getCartRecommendations(
    List<int> cartProductIds, {
    int limit = 8,
  }) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/api/v1/products/recommendations',
      queryParameters: {'ids': cartProductIds, 'limit': limit},
      options: Options(listFormat: ListFormat.multiCompatible), // ids=1&ids=2
    );
    return [
      for (final p
          in (r.data!['products'] as List).cast<Map<String, dynamic>>())
        Product.fromJson(p),
    ];
  }
}

/// Демо без бэкенда: имитирует серверный расчёт цен под тип аккаунта, чтобы UI можно было смотреть сразу.
class DemoCatalogRepository implements CatalogRepository {
  DemoCatalogRepository(this.account);
  final Account account;

  static final categories = demoCategories;
  static final _byId = {for (final i in demoItems) i.id: i};
  static const lowStockThreshold = 5;

  Product _product(int id) {
    final item = _byId[id]!;
    final retail = item.price;
    final wholesale = account.isVerifiedB2B;
    return Product(
      id: id,
      sku: 'GR-${id.toString().padLeft(4, '0')}',
      name: item.name,
      brand: item.brand,
      unit: item.unit,
      categoryId: item.categoryId,
      description:
          'Производитель: ${item.brand}. Страна происхождения: ${item.country}. '
          'Хранить при температуре от +2 до +8 °C. Отбираем вручную в день доставки.',
      imageUrls: [ingredientImage(item.image)],
      rating: 4.3 + (id % 7) / 10,
      reviewsCount: 13 * id + 7,
      specs: {'Страна': item.country},
      badges: {
        ...item.badges,
        if (item.stock <= lowStockThreshold) ProductBadge.lowStock,
      },
      stockLeft: item.stock <= lowStockThreshold ? item.stock : null,
      // Продуктовая логистика: экспресс за 2 часа, курьер сегодня/завтра, самовывоз
      delivery: const [
        DeliveryOption(
          method: DeliveryMethod.express,
          minDays: 0,
          maxDays: 0,
          price: 149,
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
      ],
      priceInfo: wholesale
          ? PriceInfo(
              price: (retail * 0.85).roundToDouble(),
              retailPrice: retail,
              compareAtPrice: retail,
              isWholesale: true,
              tiers: [
                WholesaleTier(1, (retail * 0.85).roundToDouble()),
                WholesaleTier(10, (retail * 0.80).roundToDouble()),
                WholesaleTier(50, (retail * 0.75).roundToDouble()),
              ],
            )
          : PriceInfo(
              price: retail,
              retailPrice: retail,
              compareAtPrice: item.oldPrice,
            ),
    );
  }

  List<Product> get all => [for (final i in demoItems) _product(i.id)];

  @override
  Future<CatalogSnapshot> loadCatalog() async =>
      CatalogSnapshot(categories, all);

  /// Какие категории дополняют друг друга в одной корзине (в проде это выучивает бэкенд по истории заказов).
  static const _complements = <int, List<int>>{
    1: [4, 7, 8], // овощи → зелень, масло, специи
    2: [3, 11, 12], // фрукты → ягоды, орехи, мёд
    3: [2, 12], // ягоды → фрукты, мёд
    4: [1, 7], // зелень → овощи, масло
    5: [7, 8, 9], // крупы → масло, специи, консервы
    6: [1, 7, 8, 4], // макароны → томаты, масло, специи, базилик
    7: [1, 8], // масло → овощи, специи
    8: [1, 5], // специи → овощи, крупы
    9: [6, 5], // консервы → макароны, крупы
    10: [12, 11], // чай/кофе → сахар/мёд, орехи
    11: [10, 2], // орехи → чай/кофе, фрукты
    12: [10, 3], // мука/сахар/мёд → чай/кофе, ягоды
  };

  static Map<int, int?> get _sellable => {
    for (final i in demoItems)
      if (i.stock > 0) i.id: i.categoryId,
  };

  /// «Популярность» демо-товара — по числу отзывов (в проде — по доставленным заказам).
  Map<int, int> get _popularity => {
    for (final i in demoItems) i.id: 13 * i.id + 7,
  };

  List<int> _crossSellIds(List<int> sourceIds, int limit) {
    final manual = <int, double>{};
    final complement = <int, double>{};
    final pop = _popularity;
    for (final id in sourceIds) {
      for (final (pos, t) in (demoCrossSell[id] ?? const <int>[]).indexed) {
        manual[t] = (manual[t] ?? 0) + 1 / (1 + 0.15 * pos);
      }
      // Дополняющие категории: по 2 самых популярных товара из каждой
      for (final cat in _complements[_byId[id]?.categoryId] ?? const <int>[]) {
        final top = demoItems.where((i) => i.categoryId == cat).toList()
          ..sort((a, b) => (pop[b.id] ?? 0).compareTo(pop[a.id] ?? 0));
        for (final i in top.take(2)) {
          complement[i.id] = (complement[i.id] ?? 0) + 0.5;
        }
      }
    }
    return rankCandidates(
      manual: manual,
      complement: complement,
      popularity: pop,
      sellableCategories: _sellable,
      exclude: sourceIds.toSet(),
      limit: limit,
    );
  }

  /// Upsell: ручные связи → иначе та же категория, цена ×1.0…×1.8, ближе к ×1.3 — выше.
  List<int> _similarIds(int id, {int limit = 8}) {
    final base = _byId[id]!;
    final manual = [
      for (final t in demoUpsell[id] ?? const <int>[])
        if (_sellable.containsKey(t)) t,
    ];
    final fallback =
        demoItems
            .where(
              (i) =>
                  i.categoryId == base.categoryId &&
                  i.id != id &&
                  !manual.contains(i.id) &&
                  i.stock > 0 &&
                  i.price >= base.price &&
                  i.price <= base.price * 1.8,
            )
            .toList()
          ..sort(
            (a, b) => (a.price - base.price * 1.3).abs().compareTo(
              (b.price - base.price * 1.3).abs(),
            ),
          );
    return [...manual, ...fallback.map((i) => i.id)].take(limit).toList();
  }

  @override
  Future<ProductDetails> getProduct(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return ProductDetails(
      product: _product(id),
      crossSell: [
        for (final i in _crossSellIds([id], 8)) _product(i),
      ],
      upsell: [for (final i in _similarIds(id)) _product(i)],
    );
  }

  @override
  Future<List<Product>> getCartRecommendations(
    List<int> cartProductIds, {
    int limit = 8,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return [
      for (final id in _crossSellIds(cartProductIds, limit)) _product(id),
    ];
  }
}
