import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../account/account.dart';
import '../../data/catalog_repository.dart';
import '../../domain/product.dart';

/// Репозиторий пересоздаётся при смене аккаунта → все зависимые запросы перезапускаются
/// и приходят с ценами новой аудитории. В проде: ApiCatalogRepository(ref.watch(dioProvider)).
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final account = ref.watch(accountProvider); // смена аккаунта → новые цены
  return AppConfig.isDemo
      ? DemoCatalogRepository(account)
      : ApiCatalogRepository(ref.watch(dioProvider));
});

final productDetailsProvider = FutureProvider.autoDispose
    .family<ProductDetails, int>(
      (ref, id) => ref.watch(catalogRepositoryProvider).getProduct(id),
    );

/// Избранное: optimistic update — UI реагирует мгновенно, синхронизация с API в фоне.
class FavoritesNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void toggle(int productId) => state = state.contains(productId)
      ? ({...state}..remove(productId))
      : {...state, productId};
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, Set<int>>(
  FavoritesNotifier.new,
);

@immutable
class CartEntry {
  const CartEntry(this.product, this.quantity);
  final Product product;
  final int quantity;

  double get lineTotal => product.priceInfo.unitPriceFor(quantity) * quantity;
}

/// Корзина: productId → позиция. Порядок вставки сохраняется (LinkedHashMap).
class CartNotifier extends Notifier<Map<int, CartEntry>> {
  @override
  Map<int, CartEntry> build() {
    // Вход/выход/одобрение B2B не очищает корзину — позиции перецениваются для новой аудитории.
    ref.listen(accountProvider, (_, _) => _reprice());
    return const {};
  }

  Future<void> _reprice() async {
    final repo = ref.read(catalogRepositoryProvider);
    final fresh = await Future.wait([
      for (final id in state.keys) repo.getProduct(id),
    ]);
    final byId = {for (final d in fresh) d.product.id: d.product};
    state = {
      for (final e in state.entries)
        if (byId[e.key] case final p?) e.key: CartEntry(p, e.value.quantity),
    };
  }

  void add(Product product, [int quantity = 1]) {
    final current = state[product.id]?.quantity ?? 0;
    state = {...state, product.id: CartEntry(product, current + quantity)};
  }

  void remove(int productId) {
    final entry = state[productId];
    if (entry == null) return;
    state = entry.quantity <= 1
        ? ({...state}..remove(productId))
        : {...state, productId: CartEntry(entry.product, entry.quantity - 1)};
  }

  void delete(int productId) => state = {...state}..remove(productId);
}

final cartProvider = NotifierProvider<CartNotifier, Map<int, CartEntry>>(
  CartNotifier.new,
);

final isFavoriteProvider = Provider.family<bool, int>(
  (ref, id) => ref.watch(favoritesProvider.select((s) => s.contains(id))),
);
final cartQtyProvider = Provider.family<int, int>(
  (ref, id) => ref.watch(cartProvider.select((s) => s[id]?.quantity ?? 0)),
);

/// Набор id товаров в корзине как стабильная строка-ключ: изменение *количества*
/// не должно перезапрашивать рекомендации — только изменение *состава*.
final _cartCompositionProvider = Provider<String>((ref) {
  final ids = ref.watch(cartProvider.select((s) => s.keys.toList()..sort()));
  return ids.join(',');
});

final cartRecommendationsProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) async {
  final key = ref.watch(_cartCompositionProvider);
  if (key.isEmpty) return const [];
  final repo = ref.watch(catalogRepositoryProvider);
  return repo.getCartRecommendations([
    for (final s in key.split(',')) int.parse(s),
  ]);
});

/// «Вам может понравиться» на главной: рекомендации по корзине + избранному.
/// Пусто, пока пользователь ничего не выбрал — не показываем случайные товары.
final personalRecommendationsProvider =
    FutureProvider.autoDispose<List<Product>>((ref) async {
      final cart = ref.watch(_cartCompositionProvider);
      final favorites = ref.watch(favoritesProvider);
      final ids = {
        if (cart.isNotEmpty) ...cart.split(',').map(int.parse),
        ...favorites,
      }.toList()..sort();
      if (ids.isEmpty) return const [];
      return ref
          .watch(catalogRepositoryProvider)
          .getCartRecommendations(ids, limit: 10);
    });
