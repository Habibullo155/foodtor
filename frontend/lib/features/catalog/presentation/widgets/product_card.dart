import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_image.dart';

import '../../../../core/responsive/responsive_layout.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/catalog_meta.dart';
import '../../domain/product.dart';
import '../providers/shop_providers.dart';
import 'delivery_info.dart';
import 'price_tag.dart';

/// Высота фиксирована (см. ProductSliverGrid) — ряды в сетке ровные при любом контенте.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, this.onTap});

  final Product product;
  final VoidCallback? onTap;

  /// Высота всего, что ниже квадратного фото. Используется сеткой для расчёта mainAxisExtent.
  static const double infoExtent = 206;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _HoverLift(
      enabled: context.hasPointer,
      child: Material(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Insets.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: _ImageSection(product: product),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.xs,
                      Insets.md,
                      Insets.xs,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              if (product.brand != null)
                                TextSpan(
                                  text: product.brand!.toUpperCase(),
                                  style: const TextStyle(letterSpacing: 0.6),
                                ),
                              if (product.brand != null && product.unit != null)
                                const TextSpan(text: '  ·  '),
                              if (product.unit != null)
                                TextSpan(
                                  text: product.unit,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(
                            color: context.palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: Insets.xs),
                        if (product.rating != null)
                          _Rating(
                            rating: product.rating!,
                            count: product.reviewsCount,
                          ),
                        const Spacer(),
                        PriceTag(price: product.priceInfo),
                        const SizedBox(height: Insets.xs),
                        if (product.fastestDelivery case final d?)
                          DeliveryLine(option: d),
                        const SizedBox(height: Insets.sm),
                        _CartButton(product: product),
                      ],
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

class _ImageSection extends StatelessWidget {
  const _ImageSection({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final badges = <Widget>[
      for (final b in product.badges)
        if (b != ProductBadge.lowStock) _BadgeChip(b),
      if (product.discountPercent case final pct?)
        _BadgeChip.custom(
          product.priceInfo.isWholesale ? 'ОПТ −$pct%' : '−$pct%',
          product.priceInfo.isWholesale
              ? AppColors.wholesale
              : AppColors.lowStock,
        ),
      if (product.badges.contains(ProductBadge.lowStock))
        _BadgeChip.custom(
          product.stockLeft != null
              ? 'Осталось ${product.stockLeft} шт.'
              : ProductBadge.lowStock.label,
          AppColors.lowStock,
          outlined: true,
        ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.palette.background),
          LayoutBuilder(
            builder: (context, c) => Hero(
              tag: 'product-image-${product.id}',
              child: product.imageUrls.isEmpty
                  ? Icon(
                      Icons.image_outlined,
                      color: context.palette.textSecondary,
                    )
                  // Продуктовые фото — PNG без фона: показываем целиком, с «воздухом» вокруг
                  : Padding(
                      padding: EdgeInsets.all(c.maxWidth * 0.12),
                      child: AppImage(
                        imageUrl: product.imageUrls.first,
                        fit: BoxFit.contain,
                        memCacheWidth: (c.maxWidth * dpr).round(),
                        fadeInDuration: const Duration(milliseconds: 220),
                        placeholder: (_, _) => const _Skeleton(),
                        errorWidget: (_, _, _) => Icon(
                          Icons.broken_image_outlined,
                          color: context.palette.textSecondary,
                        ),
                      ),
                    ),
            ),
          ),
          if (badges.isNotEmpty)
            Positioned(
              left: Insets.sm,
              top: Insets.sm,
              right: 48,
              child: Wrap(spacing: 4, runSpacing: 4, children: badges),
            ),
          Positioned(
            right: 6,
            top: 6,
            child: _FavoriteButton(productId: product.id),
          ),
          if (!product.inStock)
            ColoredBox(
              color: context.palette.surface.withValues(alpha: 0.75),
              child: Center(
                child: Text(
                  'Нет в наличии',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  _BadgeChip(ProductBadge badge)
    : label = badge.label,
      color = switch (badge) {
        ProductBadge.hit => AppColors.hit,
        ProductBadge.fresh => AppColors.fresh,
        ProductBadge.lowStock => AppColors.lowStock,
      },
      outlined = false;

  const _BadgeChip.custom(this.label, this.color, {this.outlined = false});

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: outlined ? context.palette.surface : color,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: outlined
            ? Border.all(color: color.withValues(alpha: 0.4))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: outlined ? color : Colors.white,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.productId});
  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(isFavoriteProvider(productId));
    return Material(
      color: context.palette.surface,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: isFav ? 'Убрать из избранного' : 'В избранное',
        visualDensity: VisualDensity.compact,
        onPressed: () {
          HapticFeedback.lightImpact();
          ref.read(favoritesProvider.notifier).toggle(productId);
        },
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
            child: child,
          ),
          child: Icon(
            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            key: ValueKey(isFav),
            size: 20,
            color: isFav ? AppColors.lowStock : context.palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _CartButton extends ConsumerWidget {
  const _CartButton({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = ref.watch(cartQtyProvider(product.id));
    final cart = ref.read(cartProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 40,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: qty == 0
            ? FilledButton.tonalIcon(
                key: const ValueKey('add'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                ),
                onPressed: product.inStock
                    ? () {
                        HapticFeedback.selectionClick();
                        cart.add(product);
                      }
                    : null,
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                label: const Text('В корзину'),
              )
            : DecoratedBox(
                key: const ValueKey('stepper'),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  children: [
                    _StepButton(
                      icon: Icons.remove_rounded,
                      onPressed: () => cart.remove(product.id),
                    ),
                    Expanded(
                      child: Text(
                        '$qty в корзине',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    _StepButton(
                      icon: Icons.add_rounded,
                      onPressed: () => cart.add(product),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: Icon(icon),
    color: Theme.of(context).colorScheme.onPrimary,
    iconSize: 18,
    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
  );
}

class _Rating extends StatelessWidget {
  const _Rating({required this.rating, required this.count});
  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFBBF24)),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(1),
          style: style?.copyWith(fontWeight: FontWeight.w600),
        ),
        Flexible(
          child: Text(
            ' · $count отзывов',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style?.copyWith(color: context.palette.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _Skeleton extends StatefulWidget {
  const _Skeleton();
  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.5, end: 1.0).animate(_c),
    child: ColoredBox(color: context.palette.skeleton),
  );
}

class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.child, required this.enabled});
  final Widget child;
  final bool enabled;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: _hovered
              ? context.palette.liftedShadow
              : context.palette.softShadow,
        ),
        child: widget.child,
      ),
    );
  }
}
