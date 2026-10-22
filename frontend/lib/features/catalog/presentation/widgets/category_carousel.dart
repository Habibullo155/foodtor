import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_image.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/catalog_filter.dart';

class CategoryCarousel extends ConsumerWidget {
  const CategoryCarousel({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: Insets.lg),
  });
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final selected = ref.watch(
      catalogFilterProvider.select((f) => f.categoryId),
    );
    final notifier = ref.read(catalogFilterProvider.notifier);

    return SizedBox(
      height: 112,
      child: ListView.separated(
        padding: padding,
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: Insets.sm),
        itemBuilder: (context, i) => i == 0
            ? _CategoryTile(
                label: 'Все',
                icon: Icons.apps_rounded,
                color: context.palette.textPrimary,
                selected: selected == null,
                onTap: () =>
                    notifier.update((f) => f.copyWith(categoryId: () => null)),
              )
            : _CategoryTile(
                label: categories[i - 1].name,
                icon: categories[i - 1].icon,
                image: categories[i - 1].imageUrl,
                color: categories[i - 1].color,
                selected: selected == categories[i - 1].id,
                onTap: () => notifier.setCategory(categories[i - 1].id),
              ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.image,
  });

  final String label;
  final IconData icon;
  final String? image;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: SizedBox(
          width: 88,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.22)
                      : color.withValues(alpha: 0.10),
                  border: Border.all(
                    color: selected ? color : Colors.transparent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(Radii.lg),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                padding: EdgeInsets.all(image == null ? 0 : 10),
                child: image == null
                    ? Icon(icon, color: color, size: 28)
                    : AppImage(
                        imageUrl: image!,
                        fit: BoxFit.contain,
                        memCacheWidth: 160,
                      ),
              ),
              const SizedBox(height: Insets.sm),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? context.palette.textPrimary
                      : context.palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
