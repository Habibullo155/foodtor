import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/widgets/app_image.dart';

import '../../../core/responsive/responsive_layout.dart';
import '../domain/product.dart';
import 'providers/shop_providers.dart';
import 'widgets/delivery_info.dart';
import 'widgets/price_tag.dart';
import 'widgets/product_rail.dart';

class ProductDetailsScreen extends ConsumerWidget {
  const ProductDetailsScreen({super.key, required this.productId});
  final int productId;

  static Route<void> route(int id) =>
      MaterialPageRoute(builder: (_) => ProductDetailsScreen(productId: id));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(productDetailsProvider(productId));
    void open(Product p) => Navigator.of(context).push(route(p.id));

    return Scaffold(
      appBar: AppBar(),
      body: details.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text('Не удалось загрузить товар')),
        data: (d) {
          final hero = Hero(
            tag: 'product-image-${d.product.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AspectRatio(
                aspectRatio: 1,
                child: ColoredBox(
                  color: context.palette.surfaceMuted,
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: AppImage(
                      imageUrl: d.product.imageUrls.firstOrNull ?? '',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          );
          final info = _Info(product: d.product);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: context.isCompact
                    ? Column(children: [hero, const SizedBox(height: 16), info])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: hero),
                          const SizedBox(width: 32),
                          Expanded(child: info),
                        ],
                      ),
              ),
              if (d.upsell.isNotEmpty)
                ProductRail(
                  title: 'Похожие товары',
                  subtitle: 'Больше памяти и лучше характеристики',
                  icon: Icons.trending_up_rounded,
                  products: d.upsell,
                  onProductTap: open,
                ),
              if (d.crossSell.isNotEmpty)
                ProductRail(
                  title: 'С этим товаром часто покупают',
                  icon: Icons.auto_awesome_rounded,
                  products: d.crossSell,
                  onProductTap: open,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Info extends ConsumerWidget {
  const _Info({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final tiers = product.priceInfo.tiers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (product.brand != null)
          Text(
            [product.brand!.toUpperCase(), ?product.unit].join('  ·  '),
            style: text.labelMedium,
          ),
        Text(
          product.name,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        PriceTag(price: product.priceInfo),
        if (tiers.length > 1) ...[
          const SizedBox(height: 12),
          Text('Оптовые цены', style: text.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tiers)
                Chip(
                  label: Text(
                    'от ${t.minQuantity} шт. — ${rub.format(t.unitPrice)}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => ref.read(cartProvider.notifier).add(product),
          icon: const Icon(Icons.add_shopping_cart_rounded),
          label: const Text('В корзину'),
        ),
        if (product.delivery.isNotEmpty) ...[
          const SizedBox(height: 20),
          DeliveryInfoCard(options: product.delivery),
        ],
        const SizedBox(height: 16),
        Text(product.description, style: text.bodyMedium),
      ],
    );
  }
}
