import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/catalog_meta.dart';
import 'price_tag.dart';

String deliveryPriceLabel(DeliveryOption o) =>
    o.isFree ? 'бесплатно' : rub.format(o.price);

class DeliveryLine extends StatelessWidget {
  const DeliveryLine({super.key, required this.option});
  final DeliveryOption option;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      children: [
        Icon(option.method.icon, size: 14, color: AppColors.fresh),
        const SizedBox(width: 4),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${option.eta}, ',
                  style: style?.copyWith(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: deliveryPriceLabel(option),
                  style: style?.copyWith(
                    color: option.isFree
                        ? AppColors.fresh
                        : context.palette.textSecondary,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class DeliveryInfoCard extends StatelessWidget {
  const DeliveryInfoCard({
    super.key,
    required this.options,
    this.city = 'Москва',
  });
  final List<DeliveryOption> options;
  final String city;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: context.palette.border),
      ),
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Доставка', style: text.titleMedium),
              const Spacer(),
              Icon(
                Icons.place_outlined,
                size: 16,
                color: context.palette.textSecondary,
              ),
              const SizedBox(width: 2),
              Text(
                city,
                style: text.labelMedium?.copyWith(
                  color: AppColors.brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: context.palette.background,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Icon(
                      o.method.icon,
                      size: 20,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.method.label,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          o.eta,
                          style: text.bodySmall?.copyWith(
                            color: context.palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    deliveryPriceLabel(o),
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: o.isFree
                          ? AppColors.fresh
                          : context.palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: Insets.xl),
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 18,
                color: context.palette.textSecondary,
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  'Возврат 14 дней · Гарантия 12 месяцев',
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
