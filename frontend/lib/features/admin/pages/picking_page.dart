import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/admin_data.dart';
import '../widgets/admin_widgets.dart';

/// Экран сборщика: только активные заказы, крупные элементы (удобно с телефона на складе),
/// чек-лист позиций и одна главная кнопка. Цен и прибыли сборщик не видит.
class PickingPage extends ConsumerWidget {
  const PickingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders =
        ref
            .watch(adminOrdersProvider)
            .where(
              (o) =>
                  o.stage == OrderStage.newOrder ||
                  o.stage == OrderStage.picking,
            )
            .toList()
          ..sort(
            (a, b) => a.createdAt.compareTo(b.createdAt),
          ); // старые — первыми

    if (orders.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.task_alt_rounded,
          title: 'Все заказы собраны',
          subtitle: 'Новые появятся здесь автоматически',
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1200 ? 3 : (c.maxWidth >= 760 ? 2 : 1);
        final w = (c.maxWidth - Insets.xl * 2 - Insets.lg * (cols - 1)) / cols;
        return ListView(
          padding: const EdgeInsets.all(Insets.xl),
          children: [
            Text(
              'В очереди: ${orders.length} · сначала самые ранние',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: context.palette.textSecondary),
            ),
            const SizedBox(height: Insets.lg),
            Wrap(
              spacing: Insets.lg,
              runSpacing: Insets.lg,
              children: [
                for (final o in orders)
                  SizedBox(
                    width: w,
                    child: _PickCard(order: o),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PickCard extends ConsumerWidget {
  const _PickCard({required this.order});
  final AdminOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(adminOrdersProvider.notifier);
    final text = Theme.of(context).textTheme;
    final picking = order.stage == OrderStage.picking;
    final done = order.lines.where((l) => l.picked).length;
    final complete = done == order.lines.length;

    return AdminCard(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: Insets.sm,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      order.number,
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    StageChip(order.stage),
                    PaymentChip(order.payment),
                  ],
                ),
              ),
              Text(
                timeAgo(order.createdAt),
                style: text.labelMedium?.copyWith(
                  color: context.palette.textSecondary,
                ),
              ),
            ],
          ),
          if (order.comment != null) ...[
            const SizedBox(height: Insets.sm),
            Container(
              padding: const EdgeInsets.all(Insets.sm),
              decoration: BoxDecoration(
                color: AppColors.hit.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.hit,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.comment!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Insets.md),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: order.pickedShare,
                    minHeight: 8,
                    backgroundColor: context.palette.background,
                    valueColor: AlwaysStoppedAnimation(
                      complete ? AppColors.fresh : AppColors.hit,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Insets.md),
              Text(
                '$done / ${order.lines.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (picking) ...[
                const SizedBox(width: Insets.sm),
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    n.pickAll(order.id);
                  },
                  icon: Icon(
                    complete
                        ? Icons.remove_done_rounded
                        : Icons.done_all_rounded,
                    size: 18,
                  ),
                  label: Text(complete ? 'Снять всё' : 'Собрать всё'),
                ),
              ],
            ],
          ),
          const SizedBox(height: Insets.sm),
          for (final (i, l) in order.lines.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: picking
                  ? () {
                      HapticFeedback.selectionClick();
                      n.togglePicked(order.id, i);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Checkbox(
                      value: l.picked,
                      onChanged: picking
                          ? (_) => n.togglePicked(order.id, i)
                          : null,
                    ),
                    ProductThumb(l.imageUrl, size: 40),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Text(
                        l.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: l.picked
                              ? TextDecoration.lineThrough
                              : null,
                          color: l.picked
                              ? context.palette.textSecondary
                              : context.palette.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.background,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Text(
                        l.unit == null ? '× ${l.qty}' : '${l.qty} × ${l.unit}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Insets.md),
          if (!picking && order.payment.blocksPicking)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: null,
              icon: const Icon(Icons.hourglass_top_rounded),
              label: const Text('Ждём онлайн-оплату — собирать рано'),
            )
          else if (!picking)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: OrderStage.picking.color,
              ),
              onPressed: () => n.setStage(order.id, OrderStage.picking),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Взять в сборку'),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppColors.fresh,
              ),
              onPressed: complete
                  ? () => n.setStage(order.id, OrderStage.shipped)
                  : null,
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(
                complete ? 'Собран — передать курьеру' : 'Отметьте все позиции',
              ),
            ),
        ],
      ),
    );
  }
}
