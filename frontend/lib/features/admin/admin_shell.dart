import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'auth/admin_auth.dart';
import 'auth/login_screen.dart';
import 'data/admin_data.dart';
import 'pages/business_page.dart';
import 'pages/catalog_pages.dart';
import 'pages/dashboard_page.dart';
import 'pages/orders_page.dart';
import 'pages/courier_page.dart';
import 'pages/delivery_page.dart';
import 'pages/picking_page.dart';
import 'pages/stories_page.dart';
import 'rbac.dart';
import '../../core/theme/theme_mode.dart';

class AdminRoot extends ConsumerWidget {
  const AdminRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminAuthProvider);
    if (ref.watch(adminBootstrapProvider).isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: session == null ? const AdminLoginScreen() : const AdminShell(),
    );
  }
}

const _groups = <(String, List<AdminSection>)>[
  ('Обзор', [AdminSection.dashboard]),
  ('Продажи', [AdminSection.orders, AdminSection.picking]),
  ('Доставка', [AdminSection.delivery, AdminSection.courier]),
  (
    'Каталог',
    [AdminSection.products, AdminSection.reviews, AdminSection.stories],
  ),
  (
    'Клиенты и команда',
    [AdminSection.business, AdminSection.loyalty, AdminSection.staff],
  ),
];

const _subtitles = {
  AdminSection.dashboard: 'Ключевые показатели магазина',
  AdminSection.orders: 'Все заказы и их статусы',
  AdminSection.picking: 'Активные заказы для сборки',
  AdminSection.courier: 'Заказы в пути: адрес, чат с покупателем, вручение',
  AdminSection.products: 'Каталог, цены, себестоимость и остатки',
  AdminSection.reviews: 'Модерация отзывов покупателей',
  AdminSection.stories: '«Кружочки» на главной сайта: акции, новинки, рецепты',
  AdminSection.business: 'Заявки компаний и минимальный оптовый заказ',
  AdminSection.loyalty: 'Уровни и скидки программы лояльности',
  AdminSection.staff: 'Сотрудники и их роли',
  AdminSection.delivery: 'Часы работы, соцсети, радиус и города доставки',
};

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  AdminSection? _current;

  @override
  Widget build(BuildContext context) {
    final sections = ref.watch(visibleSectionsProvider);
    // Ошибки загрузки/сохранения из любого раздела — одним снэкбаром
    ref.listen(adminErrorProvider, (_, msg) {
      if (msg != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    });
    if (sections.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Нет доступа к админ-панели')),
      );
    }
    final current = sections.contains(_current) ? _current! : sections.first;
    void go(AdminSection s) => setState(() => _current = s);

    final page = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: KeyedSubtree(
        key: ValueKey(current),
        child: switch (current) {
          AdminSection.dashboard => DashboardPage(
            onOpenDelivery: sections.contains(AdminSection.delivery)
                ? () => go(AdminSection.delivery)
                : null,
            onOpenOrders: sections.contains(AdminSection.orders)
                ? () => go(AdminSection.orders)
                : null,
          ),
          AdminSection.orders => const OrdersPage(),
          AdminSection.picking => const PickingPage(),
          AdminSection.courier => const CourierPage(),
          AdminSection.products => const ProductsPage(),
          AdminSection.reviews => const ReviewsPage(),
          AdminSection.stories => const StoriesPage(),
          AdminSection.loyalty => const LoyaltyPage(),
          AdminSection.staff => const StaffPage(),
          AdminSection.delivery => const DeliverySettingsPage(),
          AdminSection.business => const BusinessPage(),
        },
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        final desktop = c.maxWidth >= 1100;
        final sidebar = _Sidebar(
          sections: sections,
          current: current,
          onSelect: go,
        );
        final topBar = _TopBar(
          wide: c.maxWidth >= 760,
          section: current,
          showMenu: !desktop && sections.length > 1,
        );

        if (desktop) {
          return Scaffold(
            body: Row(
              children: [
                SizedBox(width: 264, child: sidebar),
                Expanded(
                  child: Column(
                    children: [
                      topBar,
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1440),
                            child: page,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          drawer: sections.length > 1
              ? Drawer(
                  width: 280,
                  child: _Sidebar(
                    sections: sections,
                    current: current,
                    onSelect: (s) {
                      Navigator.of(context).pop();
                      go(s);
                    },
                  ),
                )
              : null,
          body: Column(
            children: [
              topBar,
              Expanded(child: page),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.sections,
    required this.current,
    required this.onSelect,
  });
  final List<AdminSection> sections;
  final AdminSection current;
  final ValueChanged<AdminSection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final newOrders = ref.watch(
      adminOrdersProvider.select(
        (o) => o.where((x) => x.stage == OrderStage.newOrder).length,
      ),
    );
    final pendingReviews = ref.watch(
      reviewsProvider.select(
        (r) => r.where((x) => x.state == ReviewState.pending).length,
      ),
    );
    final badges = {
      AdminSection.orders: newOrders,
      AdminSection.picking: newOrders,
      AdminSection.reviews: pendingReviews,
    };

    return Material(
      color: context.palette.surface,
      shape: Border(right: BorderSide(color: context.palette.border)),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.xl,
                Insets.xl,
                Insets.xl,
                Insets.lg,
              ),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: BrandLogo(subtitle: 'Админ-панель'),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Insets.md),
                children: [
                  for (final (title, items) in _groups)
                    if (items.any(sections.contains)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Insets.md,
                          Insets.lg,
                          Insets.md,
                          Insets.sm,
                        ),
                        child: Text(
                          title.toUpperCase(),
                          style: text.labelSmall?.copyWith(
                            color: context.palette.textSecondary,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final s in items.where(sections.contains))
                        _NavItem(
                          section: s,
                          selected: s == current,
                          badge: badges[s] ?? 0,
                          onTap: () => onSelect(s),
                        ),
                    ],
                ],
              ),
            ),
            const _UserCard(),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.badge,
    required this.onTap,
  });
  final AdminSection section;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brand : context.palette.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? AppColors.brand.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: 11,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? section.selectedIcon : section.icon,
                  size: 20,
                  color: selected
                      ? AppColors.brand
                      : context.palette.textSecondary,
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    section.label,
                    style: TextStyle(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.brand : AppColors.lowStock,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserCard extends ConsumerWidget {
  const _UserCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(adminAuthProvider);
    if (s == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.all(Insets.md),
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: context.palette.background,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.brand,
            child: Text(
              s.initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  s.roleTitle,
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: () => ref.read(adminAuthProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.section,
    required this.showMenu,
    required this.wide,
  });
  final AdminSection section;
  final bool showMenu;
  final bool wide; // по ширине места (LayoutBuilder), а не окна

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final session = ref.watch(adminAuthProvider);
    final newOrders = ref.watch(
      adminOrdersProvider.select(
        (o) => o.where((x) => x.stage == OrderStage.newOrder).length,
      ),
    );

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(bottom: BorderSide(color: context.palette.border)),
      ),
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Меню',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (wide)
                  Text(
                    _subtitles[section] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (wide)
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: const TextField(
                  decoration: InputDecoration(
                    hintText: 'Поиск заказов, товаров…',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                ),
              ),
            ),
          const SizedBox(width: Insets.sm),
          const ThemeModeButton(),
          IconButton(
            tooltip: 'Уведомления',
            onPressed: () {},
            icon: Badge.count(
              count: newOrders,
              isLabelVisible: newOrders > 0,
              backgroundColor: AppColors.lowStock,
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          if (session != null)
            PopupMenuButton<String>(
              tooltip: session.name,
              offset: const Offset(0, 48),
              onSelected: (_) => ref.read(adminAuthProvider.notifier).logout(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    '${session.name}\n${session.email}',
                    style: TextStyle(color: context.palette.textPrimary),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Выйти'),
                    ],
                  ),
                ),
              ],
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.brand,
                child: Text(
                  session.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
