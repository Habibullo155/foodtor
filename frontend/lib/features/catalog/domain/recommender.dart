import 'dart:math';

/// Зеркало backend `rank_candidates` (app/services/recommendations.py) для демо-режима.
/// score = 3·manual + 1.2·complement + 0.3·popularity, затем не больше 2 товаров одной категории.
class RankedCandidate {
  const RankedCandidate(this.id, this.categoryId, this.score);
  final int id;
  final int? categoryId;
  final double score;
}

List<int> rankCandidates({
  required Map<int, double> manual,
  required Map<int, double> complement,
  required Map<int, int> popularity,
  required Map<int, int?> sellableCategories,
  required Set<int> exclude,
  required int limit,
  int maxPerCategory = 2,
}) {
  final ids = {...manual.keys, ...complement.keys}
    ..removeAll(exclude)
    ..retainWhere(sellableCategories.containsKey);
  final maxPop = ids.map((i) => popularity[i] ?? 0).fold(0, max);

  final scored =
      [
        for (final id in ids)
          RankedCandidate(
            id,
            sellableCategories[id],
            3.0 * (manual[id] ?? 0) +
                1.2 * (complement[id] ?? 0) +
                (maxPop == 0
                    ? 0
                    : 0.3 * log(1 + (popularity[id] ?? 0)) / log(1 + maxPop)),
          ),
      ]..sort(
        (a, b) => b.score != a.score
            ? b.score.compareTo(a.score)
            : a.id.compareTo(b.id),
      );

  final picked = <RankedCandidate>[], overflow = <RankedCandidate>[];
  final perCat = <int?, int>{};
  for (final c in scored) {
    if ((perCat[c.categoryId] ?? 0) < maxPerCategory) {
      picked.add(c);
      perCat[c.categoryId] = (perCat[c.categoryId] ?? 0) + 1;
    } else {
      overflow.add(c);
    }
    if (picked.length == limit) break;
  }
  return [...picked, ...overflow].take(limit).map((c) => c.id).toList();
}
