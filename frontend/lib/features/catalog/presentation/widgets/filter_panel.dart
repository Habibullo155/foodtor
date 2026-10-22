import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/catalog_filter.dart';
import 'price_tag.dart';

class FilterPanel extends ConsumerWidget {
  const FilterPanel({
    super.key,
    this.scrollController,
    this.showCategories = true,
  });

  final ScrollController? scrollController;
  final bool showCategories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(catalogFilterProvider);
    final facets = ref.watch(facetsProvider);
    final categories = ref.watch(categoriesProvider);
    final collapsed = ref.watch(categoriesCollapsedProvider);
    final n = ref.read(catalogFilterProvider.notifier);
    final text = Theme.of(context).textTheme;

    // Диапазон цен всегда в пределах фасета текущей категории (иначе RangeSlider упадёт на assert)
    final lo = facets.minPrice.floorToDouble();
    final hi = facets.maxPrice.ceilToDouble();
    final range = filter.priceRange ?? RangeValues(lo, hi);
    final safeRange = RangeValues(
      range.start.clamp(lo, hi),
      range.end.clamp(lo, hi),
    );

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        Insets.xl,
        Insets.xl,
        Insets.xl,
        Insets.xxl,
      ),
      children: [
        Row(
          children: [
            Text('Фильтры', style: text.titleLarge),
            const Spacer(),
            if (filter.activeCount > 0)
              TextButton(
                onPressed: n.resetFilters,
                child: Text('Сбросить (${filter.activeCount})'),
              ),
          ],
        ),
        if (showCategories) ...[
          Padding(
            padding: const EdgeInsets.only(top: Insets.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Категория',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: ref
                      .read(categoriesCollapsedProvider.notifier)
                      .toggle,
                  child: Text(
                    collapsed ? 'Все (${categories.length})' : 'Скрыть',
                  ),
                ),
              ],
            ),
          ),
          // Свёрнуто: остаётся только выбранная категория (или «Все товары»)
          for (final c in [null, ...categories])
            if (!collapsed || filter.categoryId == c?.id)
              _CategoryRow(
                label: c?.name ?? 'Все товары',
                icon: c?.icon ?? Icons.apps_rounded,
                selected: filter.categoryId == c?.id,
                onTap: () => n.update(
                  (f) => f.copyWith(
                    categoryId: () => c?.id,
                    priceRange: () => null,
                  ),
                ),
              ),
        ],
        _Section('Цена'),
        if (hi > lo) ...[
          Row(
            children: [
              Expanded(
                child: _PriceBox(
                  label: 'от',
                  value: rub.format(safeRange.start),
                ),
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: _PriceBox(label: 'до', value: rub.format(safeRange.end)),
              ),
            ],
          ),
          RangeSlider(
            values: safeRange,
            min: lo,
            max: hi,
            onChanged: (v) => n.update((f) => f.copyWith(priceRange: () => v)),
          ),
        ] else
          Text('Один ценовой уровень', style: text.bodySmall),
        if (facets.brands.isNotEmpty) ...[
          _Section('Бренд'),
          for (final MapEntry(key: brand, value: count)
              in facets.brands.entries)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: filter.brands.contains(brand),
              onChanged: (_) => n.toggleBrand(brand),
              title: Text(brand),
              secondary: Text(
                '$count',
                style: text.labelMedium?.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
            ),
        ],
        for (final MapEntry(key: spec, value: values)
            in facets.specs.entries) ...[
          _Section(spec),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final v in values.toList()..sort())
                FilterChip(
                  label: Text(v),
                  selected: filter.specs[spec]?.contains(v) ?? false,
                  onSelected: (_) => n.toggleSpec(spec, v),
                ),
            ],
          ),
        ],
        _Section('Наличие и доставка'),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Только в наличии'),
          value: filter.inStockOnly,
          onChanged: (v) => n.update((f) => f.copyWith(inStockOnly: v)),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Бесплатная доставка'),
          value: filter.freeDeliveryOnly,
          onChanged: (v) => n.update((f) => f.copyWith(freeDeliveryOnly: v)),
        ),
      ],
    );
  }

  static Future<void> showAsSheet(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: context.palette.surface,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (context, controller) => Column(
            children: [
              Expanded(
                child: FilterPanel(
                  scrollController: controller,
                  showCategories: false,
                ),
              ),
              const _ApplyBar(),
            ],
          ),
        ),
      );
}

class _ApplyBar extends ConsumerWidget {
  const _ApplyBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(filteredProductsProvider).length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Показать $count товаров'),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.sm),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? AppColors.brand.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: 10,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? AppColors.brand
                      : context.palette.textSecondary,
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? AppColors.brand
                          : context.palette.textPrimary,
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

class _PriceBox extends StatelessWidget {
  const _PriceBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 10),
    decoration: BoxDecoration(
      color: context.palette.background,
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(color: context.palette.textSecondary),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}
