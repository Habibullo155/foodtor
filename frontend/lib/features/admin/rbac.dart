import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Зеркало backend Permission. UI лишь *скрывает* недоступное — реальная защита на сервере.
enum Permission {
  dashboardView('dashboard:view'),
  financeView('finance:view'),
  productsRead('products:read'),
  productsWrite('products:write'),
  productsImport('products:import'),
  ordersReadAll('orders:read_all'),
  ordersPick('orders:pick'),
  ordersUpdateStatus('orders:update_status'),
  pricingManage('pricing:manage'),
  ordersDeliver('orders:deliver'),
  reviewsModerate('reviews:moderate'),
  loyaltyManage('loyalty:manage'),
  b2bManage('b2b:manage'),
  staffManage('staff:manage');

  const Permission(this.code);
  final String code;

  static Set<Permission> parse(Iterable<String> codes) => {
    for (final c in codes) ...Permission.values.where((p) => p.code == c),
  };
}

/// Разделы админки. Порядок = порядок в навигации.
enum AdminSection {
  dashboard('Дашборд', Icons.insights_outlined, Icons.insights, {
    Permission.dashboardView,
  }),
  orders('Заказы', Icons.receipt_long_outlined, Icons.receipt_long, {
    Permission.ordersReadAll,
  }),
  picking('Сборка', Icons.inventory_2_outlined, Icons.inventory_2, {
    Permission.ordersPick,
  }),
  courier(
    'Доставка заказов',
    Icons.delivery_dining_outlined,
    Icons.delivery_dining,
    {Permission.ordersDeliver},
  ),
  products('Товары', Icons.category_outlined, Icons.category, {
    Permission.productsRead,
  }),
  reviews('Отзывы', Icons.rate_review_outlined, Icons.rate_review, {
    Permission.reviewsModerate,
  }),
  stories('Истории', Icons.amp_stories_outlined, Icons.amp_stories, {
    Permission.productsWrite,
  }),
  marketing('Баннеры и бонусы', Icons.campaign_outlined, Icons.campaign, {
    Permission.productsWrite,
  }),
  support('Поддержка', Icons.support_agent_outlined, Icons.support_agent, {
    Permission.ordersReadAll,
  }),
  business('Бизнес-клиенты', Icons.storefront_outlined, Icons.storefront, {
    Permission.b2bManage,
  }),
  loyalty(
    'Лояльность',
    Icons.workspace_premium_outlined,
    Icons.workspace_premium,
    {Permission.loyaltyManage},
  ),
  staff('Сотрудники', Icons.badge_outlined, Icons.badge, {
    Permission.staffManage,
  }),
  delivery('Магазин и доставка', Icons.map_outlined, Icons.map, {
    Permission.pricingManage,
  });

  const AdminSection(this.label, this.icon, this.selectedIcon, this.required);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Set<Permission> required;
}

final permissionsProvider =
    NotifierProvider<PermissionsNotifier, Set<Permission>>(
      PermissionsNotifier.new,
    );

class PermissionsNotifier extends Notifier<Set<Permission>> {
  @override
  Set<Permission> build() => const {};
  void set(Set<Permission> value) => state = value;
}

/// Видимые разделы: Сборщик (только orders:pick) получит единственный раздел «Сборка»,
/// и AdaptiveScaffold автоматически скроет навигацию.
final visibleSectionsProvider = Provider<List<AdminSection>>((ref) {
  final perms = ref.watch(permissionsProvider);
  return [
    for (final s in AdminSection.values)
      if (perms.containsAll(s.required)) s,
  ];
});
