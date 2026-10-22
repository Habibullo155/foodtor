import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/product.dart';
import 'product_card.dart';

/// Адаптивная сетка товаров на SliverGrid.
/// Количество колонок считается от *фактической* ширины сливера (а не экрана),
/// поэтому корректно работает и рядом с сайдбаром фильтров:
///   < 600 px → 2,  < 900 → 3,  < 1280 → 4,  иначе → 5.
/// Карточки ограничены по ширине → на огромном мониторе они не раздуваются.
class ProductSliverGrid extends StatelessWidget {
  const ProductSliverGrid({
    super.key,
    required this.products,
    this.onProductTap,
  });

  final List<Product> products;
  final ValueChanged<Product>? onProductTap;

  static int columnsFor(double width) => switch (width) {
    < 600 => 2,
    < 900 => 3,
    < 1280 => 4,
    _ => 5,
  };

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final compact = width < 600;
        final spacing = compact ? Insets.md : Insets.xl;
        final padding = compact ? Insets.lg : Insets.xl;
        final columns = columnsFor(width);
        final cardWidth =
            (width - padding * 2 - spacing * (columns - 1)) / columns;

        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              // Фиксированная высота: квадратное фото (за вычетом внутренних отступов) + инфоблок
              mainAxisExtent:
                  (cardWidth - Insets.sm * 2) +
                  ProductCard.infoExtent +
                  Insets.sm * 2,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) => _Appear(
              index: i,
              child: ProductCard(
                product: products[i],
                onTap: () => onProductTap?.call(products[i]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Appear extends StatelessWidget {
  const _Appear({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = (index % 10) * 35;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay),
      curve: Interval(delay / (320 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
