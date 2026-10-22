import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/product.dart';

final rub = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 0,
);

/// Единое отображение цены во всём приложении (карточка, подборки, корзина, экран товара).
/// B2B: оптовая цена + зачёркнутая розничная + бейдж «ОПТ». B2C: цена + «старая» цена.
class PriceTag extends StatelessWidget {
  const PriceTag({
    super.key,
    required this.price,
    this.quantity = 1,
    this.dense = false,
  });

  final PriceInfo price;
  final int quantity;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unit = price.unitPriceFor(quantity);
    final strike = price.isWholesale ? price.retailPrice : price.compareAtPrice;
    final accent = price.isWholesale
        ? scheme.tertiary
        : (strike != null ? scheme.error : scheme.onSurface);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (strike != null && strike > unit)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rub.format(strike),
                style: theme.textTheme.bodySmall?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: scheme.outline,
                ),
              ),
              if (price.isWholesale) ...[
                const SizedBox(width: 6),
                const WholesaleBadge(),
              ],
            ],
          ),
        Text(
          rub.format(unit),
          style:
              (dense ? theme.textTheme.titleSmall : theme.textTheme.titleMedium)
                  ?.copyWith(fontWeight: FontWeight.w800, color: accent),
        ),
      ],
    );
  }
}

class WholesaleBadge extends StatelessWidget {
  const WholesaleBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: Text(
          'ОПТ',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
            color: scheme.onTertiaryContainer,
          ),
        ),
      ),
    );
  }
}
