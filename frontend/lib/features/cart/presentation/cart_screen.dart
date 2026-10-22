import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../../account/customer_session.dart';
import '../../account/presentation/auth_sheet.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/providers/shop_providers.dart';
import '../../catalog/presentation/widgets/price_tag.dart';
import '../../catalog/presentation/widgets/product_rail.dart';
import 'cart_checkout.dart';
import 'checkout_sheet.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key, this.onProductTap, this.onBrowse});

  final ValueChanged<Product>? onProductTap;
  final VoidCallback? onBrowse; // «Перейти в каталог» из пустой корзины

  static const desktopBreakpoint = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEmpty = ref.watch(cartProvider.select((c) => c.isEmpty));
    if (isEmpty) return _EmptyCart(onBrowse: onBrowse);

    return LayoutBuilder(
      builder: (context, c) {
        final desktop = c.maxWidth >= desktopBreakpoint;
        final pad = desktop ? Insets.xl : Insets.lg;
        final blocks = <Widget>[
          const _CartHeader(),
          const SizedBox(height: Insets.md),
          const _FreeDeliveryProgress(),
          const SizedBox(height: Insets.lg),
          const _CartItemsCard(),
          const SizedBox(height: Insets.xl),
        ];

        final upsell = <Widget>[
          FrequentlyBoughtTogether(onProductTap: onProductTap),
          const SizedBox(height: Insets.lg),
          _ForgottenItems(padding: pad),
        ];

        if (desktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(
                    top: Insets.lg,
                    bottom: Insets.xxl,
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: pad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: blocks,
                      ),
                    ),
                    ...upsell,
                  ],
                ),
              ),
              // Сводка закреплена справа и не уезжает при прокрутке
              SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    Insets.lg,
                    Insets.xl,
                    Insets.xl,
                  ),
                  child: const _SummaryCard(showCheckout: true),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(
                  top: Insets.md,
                  bottom: Insets.xl,
                ),
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: blocks,
                    ),
                  ),
                  ...upsell,
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, Insets.xl, pad, 0),
                    child: const _SummaryCard(showCheckout: false),
                  ),
                ],
              ),
            ),
            const _CheckoutBar(),
          ],
        );
      },
    );
  }
}

class _CartHeader extends ConsumerWidget {
  const _CartHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartTotalsProvider.select((t) => t.count));
    final positions = ref.watch(cartProvider.select((c) => c.length));
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      '$count ${_plural(count, 'товар', 'товара', 'товаров')}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextSpan(
                  text:
                      '  ·  $positions ${_plural(positions, 'позиция', 'позиции', 'позиций')}',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.palette.textSecondary),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Очистить корзину?'),
                content: const Text('Все товары будут удалены из корзины.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Отмена'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Очистить'),
                  ),
                ],
              ),
            );
            if (ok ?? false) {
              final notifier = ref.read(cartProvider.notifier);
              for (final id in ref.read(cartProvider).keys.toList()) {
                notifier.delete(id);
              }
            }
          },
          icon: const Icon(Icons.delete_sweep_outlined, size: 20),
          label: const Text('Очистить'),
          style: TextButton.styleFrom(
            foregroundColor: context.palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _FreeDeliveryProgress extends ConsumerWidget {
  const _FreeDeliveryProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(cartTotalsProvider);
    final reached = t.toFreeDelivery == 0;
    final color = reached ? AppColors.fresh : AppColors.brand;
    final text = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                reached
                    ? Icons.celebration_rounded
                    : Icons.local_shipping_outlined,
                color: color,
                size: 22,
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text.rich(
                  reached
                      ? const TextSpan(text: 'Доставка курьером — бесплатно')
                      : TextSpan(
                          children: [
                            const TextSpan(text: 'Добавьте ещё на '),
                            TextSpan(
                              text: rub.format(t.toFreeDelivery),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const TextSpan(
                              text: ' — и курьер привезёт бесплатно',
                            ),
                          ],
                        ),
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          TweenAnimationBuilder<double>(
            tween: Tween(end: t.freeDeliveryProgress),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemsCard extends ConsumerWidget {
  const _CartItemsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(cartProvider).values.toList();
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: context.palette.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) const Divider(indent: Insets.lg, endIndent: Insets.lg),
            _CartLineTile(key: ValueKey(e.product.id), entry: e),
          ],
        ],
      ),
    );
  }
}

class _CartLineTile extends ConsumerWidget {
  const _CartLineTile({super.key, required this.entry});
  final CartEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = entry.product;
    final cart = ref.read(cartProvider.notifier);
    final text = Theme.of(context).textTheme;
    final unitPrice = p.priceInfo.unitPriceFor(entry.quantity);
    final strikeUnit = p.priceInfo.isWholesale
        ? p.priceInfo.retailPrice
        : p.priceInfo.compareAtPrice;
    final nextTier = p.priceInfo.nextTierAfter(entry.quantity);

    void remove() {
      cart.delete(p.id);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('«${p.name}» удалён'),
            action: SnackBarAction(
              label: 'Вернуть',
              onPressed: () => cart.add(p, entry.quantity),
            ),
          ),
        );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 400;
        return Dismissible(
          key: ValueKey('line-${p.id}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => remove(),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: Insets.xl),
            color: AppColors.lowStock.withValues(alpha: 0.12),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.lowStock,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.md),
                  child: Container(
                    width: compact ? 64 : 84,
                    height: compact ? 64 : 84,
                    color: context.palette.background,
                    padding: const EdgeInsets.all(Insets.sm),
                    child: p.imageUrls.isEmpty
                        ? null
                        : AppImage(
                            imageUrl: p.imageUrls.first,
                            fit: BoxFit.contain,
                            memCacheWidth: 200,
                          ),
                  ),
                ),
                const SizedBox(width: Insets.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Удалить',
                            visualDensity: VisualDensity.compact,
                            onPressed: remove,
                            icon: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: context.palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        [
                          if (p.unit != null) p.unit!,
                          '${rub.format(unitPrice)} / шт.',
                        ].join('  ·  '),
                        style: text.bodySmall?.copyWith(
                          color: context.palette.textSecondary,
                        ),
                      ),
                      if (nextTier != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Ещё ${nextTier.minQuantity - entry.quantity} шт. — и цена ${rub.format(nextTier.unitPrice)}/шт.',
                            style: text.labelSmall?.copyWith(
                              color: AppColors.wholesale,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(height: Insets.md),
                      Row(
                        children: [
                          _QtyStepper(
                            quantity: entry.quantity,
                            onMinus: () => entry.quantity == 1
                                ? remove()
                                : cart.remove(p.id),
                            onPlus: () {
                              HapticFeedback.selectionClick();
                              cart.add(p);
                            },
                          ),
                          const SizedBox(width: Insets.sm),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (strikeUnit != null &&
                                      strikeUnit > unitPrice)
                                    Text(
                                      rub.format(strikeUnit * entry.quantity),
                                      style: text.bodySmall?.copyWith(
                                        decoration: TextDecoration.lineThrough,
                                        color: context.palette.textSecondary,
                                      ),
                                    ),
                                  Text(
                                    rub.format(entry.lineTotal),
                                    style: text.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color:
                                          strikeUnit != null &&
                                              strikeUnit > unitPrice
                                          ? AppColors.lowStock
                                          : context.palette.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.quantity,
    required this.onMinus,
    required this.onPlus,
  });
  final int quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    const tight = BoxConstraints.tightFor(width: 36, height: 36);
    return Container(
      decoration: BoxDecoration(
        color: context.palette.background,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onMinus,
            icon: Icon(
              quantity == 1
                  ? Icons.delete_outline_rounded
                  : Icons.remove_rounded,
            ),
            iconSize: 18,
            constraints: tight,
            padding: EdgeInsets.zero,
          ),
          SizedBox(
            width: 28,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Text(
                '$quantity',
                key: ValueKey(quantity),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded),
            iconSize: 18,
            constraints: tight,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// При ошибке или пустом ответе блок скрывается — рекомендации не мешают оформлению.
class FrequentlyBoughtTogether extends ConsumerWidget {
  const FrequentlyBoughtTogether({super.key, this.onProductTap});
  final ValueChanged<Product>? onProductTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(cartRecommendationsProvider);
    final anchor = ref.watch(
      cartProvider.select((cart) {
        final items = cart.values.toList()
          ..sort((a, b) => b.lineTotal.compareTo(a.lineTotal));
        return items.isEmpty ? null : items.first.product.name;
      }),
    );

    ref.listen(cartProvider, (prev, next) {
      final added = next.keys.where((id) => !(prev?.containsKey(id) ?? false));
      if (added.isEmpty || prev == null || prev.isEmpty) return;
      final product = next[added.first]!.product;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Добавлено: ${product.name}'),
            action: SnackBarAction(
              label: 'Отменить',
              onPressed: () =>
                  ref.read(cartProvider.notifier).delete(product.id),
            ),
          ),
        );
    });

    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: recs.when(
        skipLoadingOnReload: true,
        loading: () => const _RailSkeleton(),
        error: (_, _) => const SizedBox(width: double.infinity),
        data: (products) => products.isEmpty
            ? const SizedBox(width: double.infinity)
            : ProductRail(
                title: 'С этим часто покупают',
                subtitle: anchor == null
                    ? null
                    : 'К «${_short(anchor)}» обычно берут — привезём вместе',
                icon: Icons.auto_awesome_rounded,
                products: products,
                priceAsIncrement: true,
                onProductTap: onProductTap,
              ),
      ),
    );
  }

  static String _short(String s) =>
      s.length <= 28 ? s : '${s.substring(0, 27)}…';
}

class _ForgottenItems extends ConsumerWidget {
  const _ForgottenItems({required this.padding});
  final double padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(forgottenItemsProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: AppColors.hit,
                size: 22,
              ),
              const SizedBox(width: Insets.sm),
              Flexible(
                child: Text(
                  'Не забудьте купить',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              'То, что чаще всего вспоминают уже после доставки',
              style: text.bodySmall,
            ),
          ),
          const SizedBox(height: Insets.md),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 720 ? 3 : (c.maxWidth >= 420 ? 2 : 1);
              final w = (c.maxWidth - Insets.md * (cols - 1)) / cols;
              return Wrap(
                spacing: Insets.md,
                runSpacing: Insets.md,
                children: [
                  for (final p in items)
                    AnimatedSwitcher(
                      key: ValueKey(p.id),
                      duration: const Duration(milliseconds: 250),
                      child: SizedBox(
                        width: w,
                        child: _ForgottenTile(product: p),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ForgottenTile extends ConsumerWidget {
  const _ForgottenTile({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(cartProvider.notifier).add(product);
        },
        child: Container(
          padding: const EdgeInsets.all(Insets.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: context.palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.palette.background,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: AppImage(
                  imageUrl: product.imageUrls.first,
                  fit: BoxFit.contain,
                  memCacheWidth: 120,
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [rub.format(product.price), ?product.unit].join(' · '),
                      style: text.bodySmall?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.showCheckout});
  final bool showCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(cartTotalsProvider);
    final choice = ref.watch(deliveryChoiceProvider);
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Insets.xl),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: context.palette.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Способ получения',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Insets.md),
          for (final d in DeliveryChoice.values)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: _DeliveryOptionTile(
                choice: d,
                selected: d == choice,
                fee: d.feeFor(t.goods),
                onTap: () => ref.read(deliveryChoiceProvider.notifier).set(d),
              ),
            ),
          const SizedBox(height: Insets.md),
          const _PromoField(),
          const SizedBox(height: Insets.lg),
          _row(context, 'Товары (${t.count})', rub.format(t.itemsFull)),
          if (t.discount > 0)
            _row(
              context,
              t.isWholesale ? 'Оптовая выгода' : 'Скидка',
              '−${rub.format(t.discount)}',
              color: AppColors.lowStock,
            ),
          if (t.promoDiscount > 0)
            _row(
              context,
              'Промокод',
              '−${rub.format(t.promoDiscount)}',
              color: AppColors.lowStock,
            ),
          _row(
            context,
            'Доставка',
            t.delivery == 0 ? 'Бесплатно' : rub.format(t.delivery),
            color: t.delivery == 0 ? AppColors.fresh : null,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Insets.md),
            child: Divider(),
          ),
          Row(
            children: [
              Text('Итого', style: text.titleLarge),
              const SizedBox(width: Insets.md),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      rub.format(t.total),
                      key: ValueKey(t.total),
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (t.discount + t.promoDiscount > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Вы экономите ${rub.format(t.discount + t.promoDiscount)}',
                style: text.labelMedium?.copyWith(
                  color: AppColors.fresh,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (showCheckout) ...[
            const SizedBox(height: Insets.lg),
            _CheckoutButton(total: t.total),
            const SizedBox(height: Insets.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: context.palette.textSecondary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Безопасная оплата картой или СБП',
                    textAlign: TextAlign.center,
                    style: text.labelSmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: style?.copyWith(color: context.palette.textSecondary),
            ),
          ),
          Text(
            value,
            style: style?.copyWith(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _DeliveryOptionTile extends StatelessWidget {
  const _DeliveryOptionTile({
    required this.choice,
    required this.selected,
    required this.fee,
    required this.onTap,
  });
  final DeliveryChoice choice;
  final bool selected;
  final double fee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.md,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brand.withValues(alpha: 0.06)
              : context.palette.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: selected ? AppColors.brand : context.palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              choice.icon,
              size: 22,
              color: selected ? AppColors.brand : context.palette.textSecondary,
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    choice.label,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    choice.eta,
                    style: text.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              fee == 0 ? 'Бесплатно' : rub.format(fee),
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: fee == 0 ? AppColors.fresh : context.palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoField extends ConsumerStatefulWidget {
  const _PromoField();

  @override
  ConsumerState<_PromoField> createState() => _PromoFieldState();
}

class _PromoFieldState extends ConsumerState<_PromoField> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() => setState(
    () => _error = ref.read(promoProvider.notifier).apply(_controller.text),
  );

  @override
  Widget build(BuildContext context) {
    final promo = ref.watch(promoProvider);
    final shortfall = ref.watch(
      cartTotalsProvider.select((t) => t.promoShortfall),
    );

    if (promo != null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.fresh.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.local_offer_rounded,
              color: AppColors.fresh,
              size: 20,
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: Text(
                promo.amount == 0
                    ? '${promo.code}: применим при оформлении'
                    : shortfall == null
                    ? '${promo.code}: −${rub.format(promo.amount)}'
                    : '${promo.code}: добавьте ещё на ${rub.format(shortfall)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Убрать промокод',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                ref.read(promoProvider.notifier).clear();
                _controller.clear();
              },
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      );
    }

    return TextField(
      controller: _controller,
      textCapitalization: TextCapitalization.characters,
      onSubmitted: (_) => _apply(),
      decoration: InputDecoration(
        hintText: 'Промокод',
        errorText: _error,
        prefixIcon: const Icon(Icons.local_offer_outlined, size: 20),
        suffixIcon: TextButton(
          onPressed: _apply,
          child: const Text('Применить'),
        ),
      ),
    );
  }
}

class _CheckoutButton extends ConsumerWidget {
  const _CheckoutButton({required this.total});
  final double total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      onPressed: () => _checkout(context, ref),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'Оформить заказ  ·  ${rub.format(total)}',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

/// Оформление: в релизе нужен вход (заказы и адреса привязаны к аккаунту);
/// в демо покупательница уже «вошла», а заказ создаётся локально (DemoCheckoutApi).
Future<void> _checkout(BuildContext context, WidgetRef ref) async {
  final signedIn =
      AppConfig.isDemo ||
      (await ref.read(customerSessionProvider.future)) != null ||
      (context.mounted &&
          await showAuthSheet(
            context,
            reason: 'Войдите, чтобы оформить заказ и отслеживать доставку',
          ));
  if (signedIn && context.mounted) await showCheckoutSheet(context);
}

class _CheckoutBar extends ConsumerWidget {
  const _CheckoutBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(cartTotalsProvider);
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.lg,
            Insets.md,
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rub.format(t.total),
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    t.delivery == 0
                        ? 'доставка бесплатно'
                        : 'с доставкой ${rub.format(t.delivery)}',
                    style: text.labelSmall?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: Insets.lg),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: () => _checkout(context, ref),
                  child: const Text('Оформить заказ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Insets.lg),
      child: SizedBox(
        height: 260,
        // ListView, а не Row: на узком экране «лишние» плейсхолдеры обрезаются, а не переполняют layout
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
          itemBuilder: (_, _) => Container(
            width: 150,
            decoration: BoxDecoration(
              color: context.palette.skeleton,
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCart extends ConsumerWidget {
  const _EmptyCart({this.onBrowse});
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_basket_outlined,
                size: 56,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: Insets.xl),
            Text('В корзине пока пусто', style: text.titleLarge),
            const SizedBox(height: Insets.sm),
            Text(
              'Загляните в каталог — свежие овощи,\nфрукты и бакалея с доставкой за 2 часа',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
            if (onBrowse != null) ...[
              const SizedBox(height: Insets.xl),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                ),
                onPressed: onBrowse,
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Перейти в каталог'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _plural(int n, String one, String few, String many) {
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
  return many;
}
