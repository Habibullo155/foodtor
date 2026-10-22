import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_image.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/product.dart';
import '../providers/shop_providers.dart';
import 'price_tag.dart';

class ProductRail extends StatelessWidget {
  const ProductRail({
    super.key,
    required this.title,
    required this.products,
    this.subtitle,
    this.icon,
    this.priceAsIncrement = false,
    this.onProductTap,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Product> products;

  /// В корзине цена показывается как «+790 ₽» — добавка к заказу ощущается меньше полной цены.
  final bool priceAsIncrement;
  final ValueChanged<Product>? onProductTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 236,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _RailCard(
              key: ValueKey(products[i].id),
              product: products[i],
              priceAsIncrement: priceAsIncrement,
              onTap: () => onProductTap?.call(products[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _RailCard extends ConsumerWidget {
  const _RailCard({
    super.key,
    required this.product,
    required this.priceAsIncrement,
    this.onTap,
  });
  final Product product;
  final bool priceAsIncrement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final inCart = ref.watch(cartQtyProvider(product.id)) > 0;

    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.25,
                child: product.imageUrls.isEmpty
                    ? ColoredBox(color: scheme.surfaceContainerHighest)
                    : ColoredBox(
                        color: context.palette.surface, // единый фон с карточкой — без «разреза» под фото
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: AppImage(
                            imageUrl: product.imageUrls.first,
                            fit: BoxFit.contain,
                            memCacheWidth: 300,
                            errorWidget: (_, _, _) => const SizedBox(),
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (product.unit != null)
                        Text(
                          product.unit!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.outline),
                        ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: priceAsIncrement
                                ? Text(
                                    '+${rub.format(product.price)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  )
                                : PriceTag(
                                    price: product.priceInfo,
                                    dense: true,
                                  ),
                          ),
                          _QuickAdd(product: product, inCart: inCart),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAdd extends ConsumerWidget {
  const _QuickAdd({required this.product, required this.inCart});
  final Product product;
  final bool inCart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: inCart
          ? Icon(
              Icons.check_circle_rounded,
              key: const ValueKey('in'),
              color: Theme.of(context).colorScheme.primary,
            )
          : IconButton.filled(
              key: const ValueKey('add'),
              tooltip: 'Добавить в корзину',
              iconSize: 18,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              padding: EdgeInsets.zero,
              onPressed: product.inStock
                  ? () {
                      HapticFeedback.selectionClick();
                      ref.read(cartProvider.notifier).add(product);
                    }
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
    );
  }
}
