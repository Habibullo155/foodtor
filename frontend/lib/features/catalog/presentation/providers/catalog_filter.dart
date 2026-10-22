import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog_repository.dart';
import '../../domain/catalog_meta.dart';
import '../../domain/product.dart';
import 'shop_providers.dart';
import '../../../../core/theme/theme_mode.dart' show sharedPrefsProvider;

enum SortOrder {
  popular('По популярности'),
  priceAsc('Сначала дешевле'),
  priceDesc('Сначала дороже'),
  rating('По рейтингу');

  const SortOrder(this.label);
  final String label;
}

/// Состояние фильтров каталога. Иммутабельно → легко сериализовать в query-параметры URL (веб).
@immutable
class CatalogFilter {
  const CatalogFilter({
    this.query = '',
    this.categoryId,
    this.priceRange,
    this.brands = const {},
    this.specs = const {},
    this.inStockOnly = false,
    this.freeDeliveryOnly = false,
    this.sort = SortOrder.popular,
  });

  final String query;
  final int? categoryId;
  final RangeValues? priceRange;
  final Set<String> brands;
  final Map<String, Set<String>> specs; // {'Страна': {'Россия', 'Беларусь'}}
  final bool inStockOnly;
  final bool freeDeliveryOnly;
  final SortOrder sort;

  int get activeCount =>
      (priceRange != null ? 1 : 0) +
      brands.length +
      specs.values.fold<int>(0, (a, s) => a + s.length) +
      (inStockOnly ? 1 : 0) +
      (freeDeliveryOnly ? 1 : 0);

  CatalogFilter copyWith({
    String? query,
    int? Function()? categoryId,
    RangeValues? Function()? priceRange,
    Set<String>? brands,
    Map<String, Set<String>>? specs,
    bool? inStockOnly,
    bool? freeDeliveryOnly,
    SortOrder? sort,
  }) => CatalogFilter(
    query: query ?? this.query,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    priceRange: priceRange != null ? priceRange() : this.priceRange,
    brands: brands ?? this.brands,
    specs: specs ?? this.specs,
    inStockOnly: inStockOnly ?? this.inStockOnly,
    freeDeliveryOnly: freeDeliveryOnly ?? this.freeDeliveryOnly,
    sort: sort ?? this.sort,
  );

  bool matches(Product p) {
    if (query.isNotEmpty &&
        !p.name.toLowerCase().contains(query.toLowerCase())) {
      return false;
    }
    if (categoryId != null && p.categoryId != categoryId) return false;
    if (priceRange case final r? when p.price < r.start || p.price > r.end) {
      return false;
    }
    if (brands.isNotEmpty && !brands.contains(p.brand)) return false;
    for (final MapEntry(key: spec, value: allowed) in specs.entries) {
      if (allowed.isNotEmpty && !allowed.contains(p.specs[spec])) return false;
    }
    if (inStockOnly && !p.inStock) return false;
    if (freeDeliveryOnly && !p.delivery.any((d) => d.isFree)) return false;
    return true;
  }
}

class CatalogFilterNotifier extends Notifier<CatalogFilter> {
  @override
  CatalogFilter build() => const CatalogFilter();

  void update(CatalogFilter Function(CatalogFilter) change) =>
      state = change(state);
  void setQuery(String q) => state = state.copyWith(query: q);
  void setCategory(int? id) => state = state.copyWith(
    categoryId: () => state.categoryId == id ? null : id,
  );
  void toggleBrand(String brand) => state = state.copyWith(
    brands: state.brands.contains(brand)
        ? ({...state.brands}..remove(brand))
        : {...state.brands, brand},
  );
  void toggleSpec(String spec, String value) {
    final current = state.specs[spec] ?? const <String>{};
    final next = current.contains(value)
        ? ({...current}..remove(value))
        : {...current, value};
    state = state.copyWith(specs: {...state.specs, spec: next});
  }

  /// Сброс фильтров, но не категории и поиска — пользователь остаётся «в контексте».
  void resetFilters() => state = CatalogFilter(
    query: state.query,
    categoryId: state.categoryId,
    sort: state.sort,
  );
}

final catalogFilterProvider =
    NotifierProvider<CatalogFilterNotifier, CatalogFilter>(
      CatalogFilterNotifier.new,
    );

/// Все товары каталога. В проде: пагинированный GET /products?category=&brand=&price_min=… (фильтрация на сервере).
/// Загрузка каталога: в демо — мгновенно из бандла, в релизе — GET /categories + /products.
/// Перезапрашивается при смене аккаунта (вход B2B → оптовые цены).
final catalogSnapshotProvider = FutureProvider<CatalogSnapshot>(
  (ref) => ref.watch(catalogRepositoryProvider).loadCatalog(),
  // Без автоповтора Riverpod: иначе при ошибке пользователь видит бесконечный спиннер,
  // а не экран с кнопкой «Повторить»
  retry: (_, _) => null,
);

final allProductsProvider = Provider<List<Product>>(
  (ref) => ref.watch(catalogSnapshotProvider).value?.products ?? const [],
);

final categoriesProvider = Provider<List<Category>>(
  (ref) => ref.watch(catalogSnapshotProvider).value?.categories ?? const [],
);

/// Фасеты для сайдбара строятся из товаров текущей категории — пользователь не увидит
/// бренд, который даст пустую выдачу.
@immutable
class Facets {
  const Facets({
    required this.brands,
    required this.specs,
    required this.minPrice,
    required this.maxPrice,
  });
  final Map<String, int> brands; // бренд → количество товаров
  final Map<String, Set<String>> specs;
  final double minPrice;
  final double maxPrice;
}

final facetsProvider = Provider<Facets>((ref) {
  final categoryId = ref.watch(
    catalogFilterProvider.select((f) => f.categoryId),
  );
  final products = ref
      .watch(allProductsProvider)
      .where((p) => categoryId == null || p.categoryId == categoryId)
      .toList();
  final brands = <String, int>{};
  final specs = <String, Set<String>>{};
  for (final p in products) {
    if (p.brand case final b?) brands[b] = (brands[b] ?? 0) + 1;
    for (final MapEntry(:key, :value) in p.specs.entries) {
      (specs[key] ??= {}).add(value);
    }
  }
  final prices = products.map((p) => p.price);
  return Facets(
    brands: Map.fromEntries(
      brands.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    specs: specs,
    minPrice: prices.isEmpty ? 0 : prices.reduce((a, b) => a < b ? a : b),
    maxPrice: prices.isEmpty ? 0 : prices.reduce((a, b) => a > b ? a : b),
  );
});

final filteredProductsProvider = Provider<List<Product>>((ref) {
  final filter = ref.watch(catalogFilterProvider);
  final result = ref.watch(allProductsProvider).where(filter.matches).toList();
  switch (filter.sort) {
    case SortOrder.priceAsc:
      result.sort((a, b) => a.price.compareTo(b.price));
    case SortOrder.priceDesc:
      result.sort((a, b) => b.price.compareTo(a.price));
    case SortOrder.rating:
      result.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    case SortOrder.popular:
      result.sort((a, b) => b.reviewsCount.compareTo(a.reviewsCount));
  }
  return result;
});

/// «Скрыть категории»: сворачивает карусель на главной и список в фильтрах. Запоминается.
class CategoriesCollapsedNotifier extends Notifier<bool> {
  static const _key = 'categories_collapsed';

  @override
  bool build() => ref.watch(sharedPrefsProvider)?.getBool(_key) ?? false;

  void toggle() {
    state = !state;
    ref.read(sharedPrefsProvider)?.setBool(_key, state);
  }
}

final categoriesCollapsedProvider =
    NotifierProvider<CategoriesCollapsedNotifier, bool>(
      CategoriesCollapsedNotifier.new,
    );
