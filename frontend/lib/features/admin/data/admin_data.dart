import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/admin_auth.dart';
import '../domain/admin_models.dart';
import '../rbac.dart';
import '../../account/data/account_api.dart' show OrderMessage;
import 'admin_repository.dart';

export '../domain/admin_models.dart';

/// Последняя ошибка загрузки/сохранения — оболочка админки показывает её снэкбаром.
class AdminErrorNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void report(Object e) => state = e.toString();
}

final adminErrorProvider = NotifierProvider<AdminErrorNotifier, String?>(
  AdminErrorNotifier.new,
);

/// Список данных админки: в демо — сразу (seed), в релизе — загружается после входа.
/// Тип состояния — обычный List, поэтому страницы не знают, откуда данные.
abstract class RemoteListNotifier<T> extends Notifier<List<T>> {
  AdminRepository get repo => ref.read(adminRepositoryProvider);
  Future<List<T>> fetch(AdminRepository repo);

  @override
  List<T> build() {
    final session = ref.watch(adminAuthProvider);
    final seed = ref.watch(adminRepositoryProvider).seed<List<T>>();
    if (seed != null) return seed;
    if (session != null) Future.microtask(reload);
    return const [];
  }

  Future<void> reload() async {
    try {
      state = await fetch(repo);
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    }
  }

  /// Оптимистичное обновление: UI меняется сразу, при ошибке сервера — откат.
  Future<void> optimistic(List<T> next, Future<void> Function() call) async {
    final prev = state;
    state = next;
    try {
      await call();
    } catch (e) {
      state = prev;
      ref.read(adminErrorProvider.notifier).report(e);
    }
  }
}

class AdminOrdersNotifier extends RemoteListNotifier<AdminOrder> {
  @override
  Future<List<AdminOrder>> fetch(AdminRepository repo) => repo.orders(
    full: ref.read(permissionsProvider).contains(Permission.ordersReadAll),
  );

  Future<void> setStage(int id, OrderStage stage) {
    final order = state.firstWhere((o) => o.id == id);
    return optimistic([
      for (final o in state)
        if (o.id == id)
          o.copyWith(
            stage: stage,
            // наличные/карта курьеру: доставлен = деньги получены (так же решает сервер)
            paymentStatus:
                stage == OrderStage.delivered &&
                    o.paymentMethod != 'card_online'
                ? 'paid'
                : null,
          )
        else
          o,
    ], () => repo.setStage(order, stage));
  }

  /// «Собрать всё»: отметить все позиции заказа разом (или снять, если уже всё отмечено).
  void pickAll(int orderId) => state = [
    for (final o in state)
      if (o.id == orderId)
        o.copyWith(
          lines: [
            for (final l in o.lines) l.copyWith(picked: o.pickedShare < 1),
          ],
        )
      else
        o,
  ];

  /// Отметки «собрано» — локальные (чек-лист сборщика), на сервер уходит только итоговый статус.
  void togglePicked(int orderId, int lineIndex) => state = [
    for (final o in state)
      if (o.id == orderId)
        o.copyWith(
          lines: [
            for (final (i, l) in o.lines.indexed)
              i == lineIndex ? l.copyWith(picked: !l.picked) : l,
          ],
        )
      else
        o,
  ];
}

final adminOrdersProvider =
    NotifierProvider<AdminOrdersNotifier, List<AdminOrder>>(
      AdminOrdersNotifier.new,
    );

enum Period {
  week('7 дней', 7),
  twoWeeks('14 дней', 14),
  month('30 дней', 30);

  const Period(this.label, this.days);
  final String label;
  final int days;
}

class PeriodNotifier extends Notifier<Period> {
  @override
  Period build() => Period.twoWeeks;
  void set(Period p) => state = p;
}

final periodProvider = NotifierProvider<PeriodNotifier, Period>(
  PeriodNotifier.new,
);

/// История финансов: в релизе одним запросом за 2×30 дней — переключение периода не дёргает сервер.
class FinanceNotifier extends Notifier<FinanceData> {
  @override
  FinanceData build() {
    final session = ref.watch(adminAuthProvider);
    final repo = ref.watch(adminRepositoryProvider);
    final seed = repo.seed<FinanceData>();
    if (seed != null) return seed;
    if (session != null &&
        ref.read(permissionsProvider).contains(Permission.dashboardView)) {
      Future.microtask(() async {
        try {
          state = await repo.finance(30);
        } catch (e) {
          ref.read(adminErrorProvider.notifier).report(e);
        }
      });
    }
    return const FinanceData([]);
  }
}

final financeProvider = NotifierProvider<FinanceNotifier, FinanceData>(
  FinanceNotifier.new,
);
final financeHistoryProvider = Provider<List<DayFinance>>(
  (ref) => ref.watch(financeProvider).days,
);
final profitVisibleProvider = Provider<bool>(
  (ref) => ref.watch(financeProvider).profitVisible,
);

@immutable
class PeriodStats {
  const PeriodStats(this.current, this.previous);
  final List<DayFinance> current;
  final List<DayFinance> previous;

  double _sum(List<DayFinance> d, double Function(DayFinance) f) =>
      d.fold(0.0, (a, x) => a + f(x));
  double get revenue => _sum(current, (d) => d.revenue);
  double get profit => _sum(current, (d) => d.profit);
  int get orders => current.fold(0, (a, d) => a + d.orders);
  double get avgCheck => orders == 0 ? 0 : revenue / orders;
  double get margin => revenue == 0 ? 0 : profit / revenue * 100;

  double _delta(double now, double before) =>
      before == 0 ? 0 : (now - before) / before * 100;
  double get revenueDelta => _delta(revenue, _sum(previous, (d) => d.revenue));
  double get profitDelta => _delta(profit, _sum(previous, (d) => d.profit));
  double get ordersDelta => _delta(
    orders.toDouble(),
    previous.fold(0, (a, d) => a + d.orders).toDouble(),
  );
  double get avgCheckDelta {
    final prevOrders = previous.fold(0, (a, d) => a + d.orders);
    final prevAvg = prevOrders == 0
        ? 0.0
        : _sum(previous, (d) => d.revenue) / prevOrders;
    return _delta(avgCheck, prevAvg);
  }
}

final periodStatsProvider = Provider<PeriodStats>((ref) {
  final history = ref.watch(financeHistoryProvider);
  final days = ref.watch(periodProvider).days;
  // Устойчиво к короткой истории (новый магазин): берём сколько есть
  final current = history.sublist(max0(history.length - days));
  final previous = history.sublist(
    max0(history.length - days * 2),
    max0(history.length - days),
  );
  return PeriodStats(current, previous);
});

int max0(int v) => v < 0 ? 0 : v;

class AdminProductsNotifier extends RemoteListNotifier<AdminProduct> {
  @override
  Future<List<AdminProduct>> fetch(AdminRepository repo) => repo.products();

  Future<bool> save(AdminProduct p, {required bool isNew}) async {
    try {
      final saved = await repo.saveProduct(p, isNew: isNew);
      state = isNew
          ? [saved, ...state]
          : [for (final x in state) x.id == saved.id ? saved : x];
      return true;
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
      return false;
    }
  }

  Future<String?> import(String filename, List<int> bytes) async {
    try {
      final report = await repo.importProducts(filename, bytes);
      unawaited(reload());
      return report;
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
      return null;
    }
  }
}

final adminProductsProvider =
    NotifierProvider<AdminProductsNotifier, List<AdminProduct>>(
      AdminProductsNotifier.new,
    );

class AdminCategoriesNotifier extends RemoteListNotifier<AdminCategory> {
  @override
  Future<List<AdminCategory>> fetch(AdminRepository repo) => repo.categories();

  Future<AdminCategory?> create(String name, String slug) async {
    try {
      final c = await repo.createCategory(name, slug);
      state = [...state, c];
      return c;
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
      return null;
    }
  }
}

final adminCategoriesProvider =
    NotifierProvider<AdminCategoriesNotifier, List<AdminCategory>>(
      AdminCategoriesNotifier.new,
    );

typedef TopProduct = ({String name, String? imageUrl, int qty, double revenue});

final topProductsProvider = Provider<List<TopProduct>>((ref) {
  final agg = <String, TopProduct>{};
  for (final o in ref.watch(adminOrdersProvider)) {
    if (o.stage == OrderStage.cancelled) continue;
    for (final l in o.lines) {
      final key = '${l.productId ?? l.name}';
      final prev = agg[key];
      agg[key] = (
        name: l.name,
        imageUrl: l.imageUrl,
        qty: (prev?.qty ?? 0) + l.qty,
        revenue: (prev?.revenue ?? 0) + l.total,
      );
    }
  }
  return (agg.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue)))
      .take(5)
      .toList();
});

final lowStockProvider = Provider<List<AdminProduct>>(
  (ref) =>
      ref
          .watch(adminProductsProvider)
          .where((p) => p.isActive && p.stock <= 5)
          .toList()
        ..sort((a, b) => a.stock.compareTo(b.stock)),
);

class ReviewsNotifier extends RemoteListNotifier<AdminReview> {
  @override
  Future<List<AdminReview>> fetch(AdminRepository repo) => repo.reviews();

  Future<void> moderate(int id, ReviewState s) => optimistic([
    for (final r in state) r.id == id ? r.withState(s) : r,
  ], () => repo.moderate(id, approve: s == ReviewState.approved));

  /// Массовая модерация: одобрить / отклонить выбранные одним запросом.
  Future<void> moderateMany(Set<int> ids, ReviewState s) => optimistic([
    for (final r in state) ids.contains(r.id) ? r.withState(s) : r,
  ], () => repo.moderateMany(ids.toList(), approve: s == ReviewState.approved));
}

final reviewsProvider = NotifierProvider<ReviewsNotifier, List<AdminReview>>(
  ReviewsNotifier.new,
);

class TiersNotifier extends RemoteListNotifier<TierConfig> {
  @override
  Future<List<TierConfig>> fetch(AdminRepository repo) => repo.tiers();

  Future<void> create(TierConfig t) => optimistic(
    [...state, t]..sort((a, b) => a.threshold.compareTo(b.threshold)),
    () async {
      await repo.createTier(t);
      unawaited(reload());
    },
  );

  Future<void> save(TierConfig t) => optimistic(
    [for (final x in state) x.id == t.id && t.id != null ? t : x]
      ..sort((a, b) => a.threshold.compareTo(b.threshold)),
    () async {
      await repo.updateTier(t);
      unawaited(reload());
    },
  );

  Future<void> delete(TierConfig t) => optimistic(
    [
      for (final x in state)
        if (!identical(x, t)) x,
    ],
    () async {
      await repo.deleteTier(t);
      unawaited(reload());
    },
  );
}

final tiersProvider = NotifierProvider<TiersNotifier, List<TierConfig>>(
  TiersNotifier.new,
);

class StaffNotifier extends RemoteListNotifier<StaffMember> {
  @override
  Future<List<StaffMember>> fetch(AdminRepository repo) => repo.staff();

  Future<bool> create({
    required String email,
    required String name,
    required String role,
    required String password,
  }) async {
    try {
      await repo.createStaff(
        email: email,
        name: name,
        role: role,
        password: password,
      );
      await reload();
      return true;
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
      return false;
    }
  }

  /// null — ошибка (показана снэкбаром); иначе как в [AdminRepository.deleteStaff].
  Future<bool?> delete(StaffMember m) async {
    try {
      final deleted = await repo.deleteStaff(m.id);
      state = [
        for (final x in state)
          if (x.id != m.id) x,
      ];
      return deleted;
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
      return null;
    }
  }
}

final staffProvider = NotifierProvider<StaffNotifier, List<StaffMember>>(
  StaffNotifier.new,
);

final adminOrderCommentsProvider = FutureProvider.autoDispose
    .family<List<OrderMessage>, int>(
      (ref, orderId) =>
          ref.read(adminRepositoryProvider).orderComments(orderId),
    );

final deliveryZoneProvider = FutureProvider.autoDispose<DeliveryZone>(
  (ref) => ref.watch(adminRepositoryProvider).deliveryZone(),
);

final workHoursProvider = FutureProvider.autoDispose<WorkHours>(
  (ref) => ref.watch(adminRepositoryProvider).workHours(),
);

final socialsProvider = FutureProvider.autoDispose<ShopSocials>(
  (ref) => ref.watch(adminRepositoryProvider).socials(),
);

class CompaniesNotifier extends RemoteListNotifier<B2BCompany> {
  @override
  Future<List<B2BCompany>> fetch(AdminRepository repo) => repo.companies();

  Future<bool> decide(
    B2BCompany c, {
    required bool approve,
    String? note,
  }) async {
    try {
      await repo.decideCompany(c.id, approve: approve, note: note);
      state = [
        for (final x in state)
          x.id == c.id ? x.decided(approve: approve, note: note) : x,
      ];
      return true;
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
      return false;
    }
  }
}

final companiesProvider = NotifierProvider<CompaniesNotifier, List<B2BCompany>>(
  CompaniesNotifier.new,
);

final wholesaleMinOrderProvider = FutureProvider.autoDispose<double>(
  (ref) => ref.watch(adminRepositoryProvider).wholesaleMinOrder(),
);

class StoriesNotifier extends RemoteListNotifier<AdminStory> {
  @override
  Future<List<AdminStory>> fetch(AdminRepository repo) => repo.stories();

  Future<bool> save(AdminStory s) async {
    try {
      final saved = await repo.saveStory(s);
      state = s.id == 0
          ? [...state, saved]
          : [for (final x in state) x.id == saved.id ? saved : x];
      return true;
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
      return false;
    }
  }

  Future<void> toggle(AdminStory s) => save(s.copyWith(isActive: !s.isActive));

  Future<void> delete(AdminStory s) => optimistic([
    for (final x in state)
      if (x.id != s.id) x,
  ], () => repo.deleteStory(s.id));

  Future<void> move(AdminStory s, int delta) {
    final list = [...state];
    final i = list.indexWhere((x) => x.id == s.id);
    final j = i + delta;
    if (j < 0 || j >= list.length) return Future.value();
    list.insert(j, list.removeAt(i));
    return optimistic(
      list,
      () => repo.reorderStories([for (final x in list) x.id]),
    );
  }
}

final storiesProvider = NotifierProvider<StoriesNotifier, List<AdminStory>>(
  StoriesNotifier.new,
);

class CourierOrdersNotifier extends RemoteListNotifier<CourierOrder> {
  @override
  Future<List<CourierOrder>> fetch(AdminRepository repo) =>
      repo.courierOrders();

  Future<void> _apply(Future<CourierOrder> Function() call) async {
    try {
      final o = await call();
      state = [
        for (final x in state)
          if (x.id != o.id) x else if (!o.delivered) o,
      ];
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    }
  }

  Future<void> take(int id) => _apply(() => repo.takeOrder(id));
  Future<void> locate(int id, double lat, double lng) =>
      _apply(() => repo.sendLocation(id, lat, lng));
  Future<void> emergency(int id, String reason) =>
      _apply(() => repo.emergency(id, reason));
  Future<void> delivered(int id) => _apply(() => repo.markDelivered(id));
}

final courierOrdersProvider =
    NotifierProvider<CourierOrdersNotifier, List<CourierOrder>>(
      CourierOrdersNotifier.new,
    );
