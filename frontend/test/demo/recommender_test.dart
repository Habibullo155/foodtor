import 'package:flutter_test/flutter_test.dart';
import 'package:saasshop/features/account/account.dart';
import 'package:saasshop/features/catalog/data/catalog_repository.dart';
import 'package:saasshop/features/catalog/domain/recommender.dart';

void main() {
  test('manual links win, cart items excluded, unsellable dropped', () {
    final r = rankCandidates(
      manual: {3: 1, 4: 1},
      complement: {5: 0.5},
      popularity: {3: 1, 4: 1, 5: 100},
      sellableCategories: {3: 1, 5: 2, 9: 1},
      exclude: {9},
      limit: 5,
    );
    expect(r, [3, 5]); // 4 нет в наличии, 9 в корзине
  });

  test('diversity: at most two per category before the tail', () {
    final r = rankCandidates(
      manual: {1: 1, 2: 0.9, 3: 0.8, 4: 0.1},
      complement: {},
      popularity: {},
      sellableCategories: {1: 1, 2: 1, 3: 1, 4: 2},
      exclude: {},
      limit: 4,
    );
    expect(r, [1, 2, 4, 3]);
  });

  test(
    'demo: tomatoes bring cucumbers/greens, never the tomatoes themselves',
    () async {
      final repo = DemoCatalogRepository(Account.guest);
      final recs = await repo.getCartRecommendations([1]);
      expect(recs.first.name, contains('Огурцы'));
      expect(recs.map((p) => p.id), isNot(contains(1)));
      final cats = <int?, int>{};
      for (final p in recs) {
        cats[p.categoryId] = (cats[p.categoryId] ?? 0) + 1;
      }
      expect(cats.values.take(recs.length - 1).every((n) => n <= 3), isTrue);
    },
  );

  test(
    'demo: similar falls back to pricier items of the same category',
    () async {
      final repo = DemoCatalogRepository(Account.guest);
      final d = await repo.getProduct(5); // Морковь 69 ₽ — ручных upsell нет
      expect(d.upsell, isNotEmpty);
      for (final p in d.upsell) {
        expect(p.categoryId, d.product.categoryId);
        expect(
          p.price,
          inInclusiveRange(d.product.price, d.product.price * 1.8),
        );
      }
    },
  );
}
