import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../account/account.dart';
import '../../catalog/presentation/widgets/price_tag.dart';
import 'home_providers.dart';
import 'search_field.dart';
import '../../../core/theme/theme_mode.dart';

class DesktopHeader extends ConsumerWidget implements PreferredSizeWidget {
  const DesktopHeader({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final HomeTab current;
  final ValueChanged<HomeTab> onSelect;

  static const double height = 76;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(headerCountsProvider);
    final isB2B = ref.watch(accountProvider.select((a) => a.isVerifiedB2B));

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(bottom: BorderSide(color: context.palette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
      child: Row(
        children: [
          SizedBox(
            width: 264, // совпадает с шириной сайдбара — поиск визуально над контентом
            child: InkWell(
              onTap: () => onSelect(HomeTab.home),
              borderRadius: BorderRadius.circular(Radii.sm),
              child: const Padding(
                padding: EdgeInsets.all(Insets.xs),
                child: AppLogo(),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: CatalogSearchField(
                  onSubmitted: () => onSelect(HomeTab.home),
                ),
              ),
            ),
          ),
          const SizedBox(width: Insets.xl),
          const ThemeModeButton(),
          const SizedBox(width: Insets.sm),
          if (isB2B)
            const Padding(
              padding: EdgeInsets.only(right: Insets.md),
              child: WholesaleBadge(),
            ),
          _HeaderAction(
            icon: Icons.favorite_border_rounded,
            activeIcon: Icons.favorite_rounded,
            label: 'Избранное',
            count: counts.favorites,
            active: current == HomeTab.favorites,
            onTap: () => onSelect(HomeTab.favorites),
          ),
          _HeaderAction(
            icon: Icons.shopping_bag_outlined,
            activeIcon: Icons.shopping_bag_rounded,
            label: 'Корзина',
            count: counts.cart,
            active: current == HomeTab.cart,
            onTap: () => onSelect(HomeTab.cart),
          ),
          _HeaderAction(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: 'Профиль',
            active: current == HomeTab.profile,
            onTap: () => onSelect(HomeTab.profile),
          ),
        ],
      ),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: BrandLogo(),
        ),
      ),
    ],
  );
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.count = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.brand : context.palette.textPrimary;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge.count(
                count: count,
                isLabelVisible: count > 0,
                backgroundColor: AppColors.lowStock,
                child: Icon(active ? activeIcon : icon, color: color, size: 24),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
