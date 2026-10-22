import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../account/presentation/profile_page.dart';
import '../../cart/presentation/cart_screen.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/product_details_screen.dart';
import '../../catalog/presentation/providers/catalog_filter.dart';
import '../../catalog/presentation/providers/shop_providers.dart';
import '../../catalog/presentation/widgets/category_carousel.dart';
import '../../catalog/presentation/widgets/filter_panel.dart';
import '../../catalog/presentation/widgets/price_tag.dart';
import '../../catalog/presentation/widgets/product_rail.dart';
import '../../catalog/presentation/widgets/product_sliver_grid.dart';
import '../../legal/legal_pages.dart';
import '../../stories/domain/story.dart';
import '../../stories/presentation/stories_strip.dart';
import 'desktop_header.dart';
import 'home_providers.dart';
import 'payment_return.dart';
import 'search_field.dart';
import '../../../core/theme/theme_mode.dart';

/// Точка ветвления лейаута. Ширина берётся из LayoutBuilder (доступное место, а не экран),
/// поэтому ресайз окна на ПК/вебе переключает лейаут «на лету».
///
///   < 1024 px → MobileHomeLayout:  SliverAppBar с поиском + Bottom Navigation Bar,
///                                  фильтры — в bottom sheet.
///   ≥ 1024 px → DesktopHomeLayout: Top Header (логотип, поиск по центру, иконки с бейджами)
///                                  + левый сайдбар с глубокими фильтрами.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  static const desktopBreakpoint = 1024.0;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  HomeTab _tab = HomeTab.home;

  @override
  void initState() {
    super.initState();
    // Вернулись со страницы банка → показать результат оплаты и открыть профиль с заказами
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || parsePaymentReturn(Uri.base) == null) return;
      setState(() => _tab = HomeTab.profile);
      await handlePaymentReturn(context, ref);
    });
  }

  void _select(HomeTab tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= HomeScreen.desktopBreakpoint;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: isDesktop
              ? DesktopHomeLayout(
                  key: const ValueKey('desktop'),
                  tab: _tab,
                  onSelect: _select,
                )
              : MobileHomeLayout(
                  key: const ValueKey('mobile'),
                  tab: _tab,
                  onSelect: _select,
                ),
        );
      },
    );
  }
}

void _openProduct(BuildContext context, Product p) =>
    Navigator.of(context).push(ProductDetailsScreen.route(p.id));

class MobileHomeLayout extends ConsumerWidget {
  const MobileHomeLayout({
    super.key,
    required this.tab,
    required this.onSelect,
  });
  final HomeTab tab;
  final ValueChanged<HomeTab> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(headerCountsProvider);
    return Scaffold(
      // IndexedStack сохраняет позицию скролла каждой вкладки
      body: IndexedStack(
        index: tab.index,
        children: [
          const HomeFeed(isDesktop: false),
          const _TabPage(title: 'Избранное', child: FavoritesView()),
          _TabPage(
            title: 'Корзина',
            child: CartScreen(
              onProductTap: (p) => _openProduct(context, p),
              onBrowse: () => onSelect(HomeTab.home),
            ),
          ),
          const _TabPage(title: 'Профиль', child: ProfilePage()),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.palette.border)),
        ),
        child: NavigationBar(
          selectedIndex: tab.index,
          onDestinationSelected: (i) => onSelect(HomeTab.values[i]),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Главная',
            ),
            NavigationDestination(
              icon: _CountBadge(
                count: counts.favorites,
                child: const Icon(Icons.favorite_border_rounded),
              ),
              selectedIcon: _CountBadge(
                count: counts.favorites,
                child: const Icon(Icons.favorite_rounded),
              ),
              label: 'Избранное',
            ),
            NavigationDestination(
              icon: _CountBadge(
                count: counts.cart,
                child: const Icon(Icons.shopping_bag_outlined),
              ),
              selectedIcon: _CountBadge(
                count: counts.cart,
                child: const Icon(Icons.shopping_bag_rounded),
              ),
              label: 'Корзина',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Профиль',
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPage extends StatelessWidget {
  const _TabPage({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Badge.count(
    count: count,
    isLabelVisible: count > 0,
    backgroundColor: AppColors.lowStock,
    child: child,
  );
}

class DesktopHomeLayout extends StatelessWidget {
  const DesktopHomeLayout({
    super.key,
    required this.tab,
    required this.onSelect,
  });
  final HomeTab tab;
  final ValueChanged<HomeTab> onSelect;

  static const sidebarWidth = 288.0;

  @override
  Widget build(BuildContext context) {
    Widget centered(Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: child,
      ),
    );

    return Scaffold(
      appBar: DesktopHeader(current: tab, onSelect: onSelect),
      body: IndexedStack(
        index: tab.index,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Сайдбар — не меню, а глубокие фильтры (категория, цена, бренд, характеристики, доставка)
              // Material (а не Container с цветом): ripple-эффекты ListTile рисуются на ближайшем Material
              SizedBox(
                width: sidebarWidth,
                child: Material(
                  color: context.palette.surface,
                  shape: Border(
                    right: BorderSide(color: context.palette.border),
                  ),
                  child: FilterPanel(),
                ),
              ),
              const Expanded(child: HomeFeed(isDesktop: true)),
            ],
          ),
          centered(
            const _DesktopSection(title: 'Избранное', child: FavoritesView()),
          ),
          centered(
            _DesktopSection(
              title: 'Корзина',
              child: CartScreen(
                onProductTap: (p) => _openProduct(context, p),
                onBrowse: () => onSelect(HomeTab.home),
              ),
            ),
          ),
          centered(
            const _DesktopSection(title: 'Профиль', child: ProfilePage()),
          ),
        ],
      ),
    );
  }
}

class _DesktopSection extends StatelessWidget {
  const _DesktopSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.xl,
          Insets.xxl,
          Insets.xl,
          Insets.sm,
        ),
        child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ),
      Expanded(child: child),
    ],
  );
}

/// Лента главного экрана: Stories → Категории → панель сортировки → сетка товаров.
/// Общая для обоих лейаутов; отличаются только шапка и способ показа фильтров.
class HomeFeed extends ConsumerWidget {
  const HomeFeed({super.key, required this.isDesktop});
  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(filteredProductsProvider);
    final catalog = ref.watch(catalogSnapshotProvider);
    final storeIsEmpty = catalog.hasValue && catalog.value!.products.isEmpty;
    final hasStories = ref.watch(storiesProvider.select((s) => s.isNotEmpty));
    final hPad = isDesktop ? Insets.xl : Insets.lg;

    final slivers = <Widget>[
      if (!isDesktop) const _MobileAppBar(),
      SliverToBoxAdapter(
        child: SizedBox(height: isDesktop ? Insets.xl : Insets.lg),
      ),
      if (hasStories)
        SliverToBoxAdapter(
          child: StoriesStrip(padding: EdgeInsets.symmetric(horizontal: hPad)),
        ),
      if (ref.watch(categoriesProvider).isNotEmpty) ...[
        SliverToBoxAdapter(child: _CategoriesHeader(padding: hPad)),
        if (!ref.watch(categoriesCollapsedProvider))
          SliverToBoxAdapter(
            child: CategoryCarousel(
              padding: EdgeInsets.symmetric(horizontal: hPad),
            ),
          ),
      ],
      const SliverToBoxAdapter(child: _PersonalPicks()),
      SliverToBoxAdapter(
        child: _FeedToolbar(
          isDesktop: isDesktop,
          count: products.length,
          padding: hPad,
        ),
      ),
      if (catalog.isLoading && !catalog.hasValue)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _CatalogLoading(),
        )
      else if (catalog.hasError && !catalog.hasValue)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _CatalogError(message: catalog.error.toString()),
        )
      else if (storeIsEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _StoreComingSoon(),
        )
      else if (products.isEmpty)
        const SliverFillRemaining(hasScrollBody: false, child: _EmptyResults())
      else
        ProductSliverGrid(
          products: products,
          onProductTap: (p) => _openProduct(context, p),
        ),
      const SliverToBoxAdapter(child: SiteFooter()),
    ];

    final scroll = CustomScrollView(slivers: slivers);
    if (!isDesktop) return scroll;
    // На ультрашироких мониторах лента не растягивается бесконечно
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1480),
        child: scroll,
      ),
    );
  }
}

class _MobileAppBar extends StatelessWidget {
  const _MobileAppBar();

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      floating: true,
      backgroundColor: context.palette.surface,
      toolbarHeight: 60,
      titleSpacing: Insets.lg,
      title: Row(
        children: [
          const Expanded(
            child: Align(alignment: Alignment.centerLeft, child: AppLogo()),
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.place_outlined, size: 18),
            label: const Text('Москва'),
          ),
          const ThemeModeButton(),
        ],
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(64),
        child: Padding(
          padding: EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.md),
          child: CatalogSearchField(),
        ),
      ),
    );
  }
}

class _CategoriesHeader extends ConsumerWidget {
  const _CategoriesHeader({required this.padding});
  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(categoriesCollapsedProvider);
    final count = ref.watch(categoriesProvider).length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding,
        Insets.xl,
        padding - Insets.sm,
        collapsed ? 0 : Insets.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Категории',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          TextButton.icon(
            onPressed: ref.read(categoriesCollapsedProvider.notifier).toggle,
            iconAlignment: IconAlignment.end,
            icon: Icon(
              collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
            ),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            label: Text(collapsed ? 'Показать ($count)' : 'Скрыть'),
          ),
        ],
      ),
    );
  }
}

class _FeedToolbar extends ConsumerWidget {
  const _FeedToolbar({
    required this.isDesktop,
    required this.count,
    required this.padding,
  });
  final bool isDesktop;
  final int count;
  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(catalogFilterProvider);
    final categories = ref.watch(categoriesProvider);
    final n = ref.read(catalogFilterProvider.notifier);
    final text = Theme.of(context).textTheme;

    final title = filter.query.isNotEmpty
        ? 'Поиск: «${filter.query}»'
        : categories
                  .where((c) => c.id == filter.categoryId)
                  .firstOrNull
                  ?.name ??
              'Рекомендуем для вас';

    final sort = PopupMenuButton<SortOrder>(
      tooltip: 'Сортировка',
      initialValue: filter.sort,
      onSelected: (s) => n.update((f) => f.copyWith(sort: s)),
      itemBuilder: (_) => [
        for (final s in SortOrder.values)
          PopupMenuItem(value: s, child: Text(s.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.sm,
          vertical: Insets.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert_rounded, size: 20),
            const SizedBox(width: 4),
            Text(filter.sort.label, style: text.labelLarge),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, Insets.xl, padding, Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title, style: text.titleLarge),
                      TextSpan(
                        text: '  $count',
                        style: text.titleMedium?.copyWith(
                          color: context.palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isDesktop)
                sort
              else
                Badge.count(
                  count: filter.activeCount,
                  isLabelVisible: filter.activeCount > 0,
                  child: IconButton.outlined(
                    tooltip: 'Фильтры',
                    onPressed: () => FilterPanel.showAsSheet(context),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ),
            ],
          ),
          if (!isDesktop) Align(alignment: Alignment.centerLeft, child: sort),
          if (isDesktop && filter.activeCount > 0) ...[
            const SizedBox(height: Insets.md),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                if (filter.priceRange case final r?)
                  InputChip(
                    label: Text(
                      '${rub.format(r.start)} – ${rub.format(r.end)}',
                    ),
                    onDeleted: () =>
                        n.update((f) => f.copyWith(priceRange: () => null)),
                  ),
                for (final b in filter.brands)
                  InputChip(label: Text(b), onDeleted: () => n.toggleBrand(b)),
                for (final MapEntry(key: spec, value: values)
                    in filter.specs.entries)
                  for (final v in values)
                    InputChip(
                      label: Text(v),
                      onDeleted: () => n.toggleSpec(spec, v),
                    ),
                if (filter.inStockOnly)
                  InputChip(
                    label: const Text('В наличии'),
                    onDeleted: () =>
                        n.update((f) => f.copyWith(inStockOnly: false)),
                  ),
                if (filter.freeDeliveryOnly)
                  InputChip(
                    label: const Text('Бесплатная доставка'),
                    onDeleted: () =>
                        n.update((f) => f.copyWith(freeDeliveryOnly: false)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyResults extends ConsumerWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(Insets.xxl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.search_off_rounded,
          size: 56,
          color: context.palette.textSecondary,
        ),
        const SizedBox(height: Insets.md),
        Text(
          'Ничего не нашлось',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Insets.xs),
        Text(
          'Попробуйте изменить фильтры или запрос',
          style: TextStyle(color: context.palette.textSecondary),
        ),
        const SizedBox(height: Insets.lg),
        OutlinedButton(
          onPressed: () => ref
              .read(catalogFilterProvider.notifier)
              .update((_) => const CatalogFilter()),
          child: const Text('Сбросить всё'),
        ),
      ],
    ),
  );
}

class FavoritesView extends ConsumerWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(favoritesProvider);
    final products = ref
        .watch(allProductsProvider)
        .where((p) => ids.contains(p.id))
        .toList();
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              size: 56,
              color: context.palette.textSecondary,
            ),
            SizedBox(height: Insets.md),
            Text('Добавляйте товары в избранное, нажимая ♡'),
          ],
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: Insets.lg)),
        ProductSliverGrid(
          products: products,
          onProductTap: (p) => _openProduct(context, p),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Insets.xxl)),
      ],
    );
  }
}

/// Персональная лента на главной — появляется плавно, когда есть корзина/избранное.
class _PersonalPicks extends ConsumerWidget {
  const _PersonalPicks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picks = ref.watch(personalRecommendationsProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: switch (picks) {
        AsyncData(:final value) when value.isNotEmpty => Padding(
          padding: const EdgeInsets.only(top: Insets.xl),
          child: ProductRail(
            title: 'Вам может понравиться',
            subtitle: 'Подобрали по вашей корзине и избранному',
            icon: Icons.favorite_outline_rounded,
            products: value,
            onProductTap: (p) => _openProduct(context, p),
          ),
        ),
        _ => const SizedBox(width: double.infinity),
      },
    );
  }
}

class _CatalogLoading extends StatelessWidget {
  const _CatalogLoading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(Insets.xxl),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _CatalogError extends ConsumerWidget {
  const _CatalogError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(Insets.xxl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: 56,
          color: context.palette.textSecondary,
        ),
        const SizedBox(height: Insets.md),
        Text(
          'Не удалось загрузить каталог',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Insets.xs),
        Text(message, style: TextStyle(color: context.palette.textSecondary)),
        const SizedBox(height: Insets.lg),
        FilledButton.icon(
          onPressed: () => ref.invalidate(catalogSnapshotProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Повторить'),
        ),
      ],
    ),
  );
}

/// Релиз с пустой базой: магазин ещё не наполнен товарами.
class _StoreComingSoon extends StatelessWidget {
  const _StoreComingSoon();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(Insets.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: AppColors.fresh.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_outlined,
              size: 52,
              color: AppColors.fresh,
            ),
          ),
          const SizedBox(height: Insets.xl),
          Text('Скоро открытие', style: text.headlineSmall),
          const SizedBox(height: Insets.sm),
          Text(
            'Мы раскладываем свежие овощи, фрукты и бакалею по полкам.\nЗагляните чуть позже!',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
