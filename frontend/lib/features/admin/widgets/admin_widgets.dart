import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../data/admin_data.dart';

final _compact = NumberFormat.compact(locale: 'ru');
final money = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 0,
);

/// «1,2 млн ₽» для KPI и осей графиков.
String moneyCompact(num v) => '${_compact.format(v)} ₽';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
  if (d.inHours < 24) return '${d.inHours} ч назад';
  return DateFormat('d MMM, HH:mm', 'ru').format(t);
}

class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    this.title,
    this.subtitle,
    this.action,
    required this.child,
    this.padding,
  });

  final String? title;
  final String? subtitle;
  final Widget? action;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Material, а не Container с цветом: ListTile/InkWell внутри карточки рисуют ripple на нём
    return Material(
      color: context.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: BorderSide(color: context.palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(Insets.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: text.bodySmall?.copyWith(
                              color: context.palette.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
              const SizedBox(height: Insets.lg),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class StageChip extends StatelessWidget {
  const StageChip(this.stage, {super.key});
  final OrderStage stage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: stage.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: stage.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            stage.label,
            style: TextStyle(
              color: stage.color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentChip extends StatelessWidget {
  const PaymentChip(this.payment, {super.key});
  final PaymentState payment;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Оплата',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: payment.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(payment.icon, size: 13, color: payment.color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              payment.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: payment.color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class DeltaChip extends StatelessWidget {
  const DeltaChip(this.percent, {super.key});
  final double percent;

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final color = up ? AppColors.fresh : AppColors.lowStock;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            '${percent.abs().toStringAsFixed(1).replaceAll('.', ',')}%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class ProductThumb extends StatelessWidget {
  const ProductThumb(this.imageUrl, {super.key, this.size = 44});
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * 0.12),
    decoration: BoxDecoration(
      color: context.palette.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: imageUrl == null
        ? Icon(
            Icons.image_outlined,
            size: size * 0.5,
            color: context.palette.textSecondary,
          )
        : AppImage(
            imageUrl: imageUrl!,
            fit: BoxFit.contain,
            memCacheWidth: 120,
          ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Insets.xxl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 34, color: AppColors.brand),
        ),
        const SizedBox(height: Insets.lg),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.palette.textSecondary),
          ),
        ],
      ],
    ),
  );
}

class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.children,
    this.flex,
    this.breakpoint = 900,
  });
  final List<Widget> children;
  final List<int>? flex;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, w) in children.indexed) ...[
                if (i > 0) const SizedBox(height: Insets.lg),
                w,
              ],
            ],
          );
        }
        // Без IntrinsicHeight: графики fl_chart не поддерживают intrinsic-измерения
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, w) in children.indexed) ...[
              if (i > 0) const SizedBox(width: Insets.lg),
              Expanded(flex: flex?[i] ?? 1, child: w),
            ],
          ],
        );
      },
    );
  }
}
