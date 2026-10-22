import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/presentation/providers/shop_providers.dart';

enum HomeTab { home, favorites, cart, profile }

@immutable
class HeaderCounts {
  const HeaderCounts(this.cart, this.favorites);
  final int cart;
  final int favorites;

  @override
  bool operator ==(Object other) =>
      other is HeaderCounts &&
      other.cart == cart &&
      other.favorites == favorites;

  @override
  int get hashCode => Object.hash(cart, favorites);
}

/// Счётчики для бейджей в шапке и нижней навигации. Равенство по значению →
/// шапка не перерисовывается, пока числа не изменились.
final headerCountsProvider = Provider<HeaderCounts>((ref) {
  final cart = ref.watch(
    cartProvider.select((c) => c.values.fold(0, (a, e) => a + e.quantity)),
  );
  final favorites = ref.watch(favoritesProvider.select((f) => f.length));
  return HeaderCounts(cart, favorites);
});
