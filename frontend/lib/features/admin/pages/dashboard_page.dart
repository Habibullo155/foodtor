import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../auth/admin_auth.dart';
import '../data/admin_data.dart';
import '../widgets/admin_widgets.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, this.onOpenOrders, this.onOpenDelivery});
  final VoidCallback? onOpenOrders;
  final VoidCallback? onOpenDelivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        const _Greeting(),
        if (onOpenDelivery != null) ...[
          const SizedBox(height: Insets.lg),
          _DeliveryZoneBanner(onOpen: onOpenDelivery!),
        ],
        const SizedBox(height: Insets.xl),
        const _KpiGrid(),
        const SizedBox(height: Insets.lg),
        const ResponsiveRow(
          flex: [2, 1],
          breakpoint: 1000,
          children: [_RevenueChartCard(), _OrdersByStageCard()],
        ),
        const SizedBox(height: Insets.lg),
        ResponsiveRow(
          breakpoint: 1000,
          flex: const [3, 2],
          children: [
            _RecentOrdersCard(onOpenOrders: onOpenOrders),
            const _TopProductsCard(),
          ],
        ),
        const SizedBox(height: Insets.lg),
        const _LowStockCard(),
      ],
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(adminAuthProvider)?.firstName ?? '';
    final hour = DateTime.now().hour;
    final hello = hour < 12
        ? 'Доброе утро'
        : (hour < 18 ? 'Добрый день' : 'Добрый вечер');
    final text = Theme.of(context).textTheme;
    final period = ref.watch(periodProvider);

    return Wrap(
      spacing: Insets.lg,
      runSpacing: Insets.md,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$hello, $name 👋',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Сводка магазина · ${DateFormat('d MMMM, EEEE', 'ru').format(DateTime.now())}',
              style: text.bodyMedium?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
          ],
        ),
        SegmentedButton<Period>(
          showSelectedIcon: false,
          segments: [
            for (final p in Period.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {period},
          onSelectionChanged: (s) =>
              ref.read(periodProvider.notifier).set(s.first),
        ),
      ],
    );
  }
}

class _KpiGrid extends ConsumerWidget {
  const _KpiGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(periodStatsProvider);
    final showProfit = ref.watch(profitVisibleProvider);
    final cards = [
      _Kpi(
        'Выручка',
        moneyCompact(s.revenue),
        s.revenueDelta,
        Icons.payments_outlined,
        AppColors.brand,
      ),
      if (showProfit)
        _Kpi(
          'Чистая прибыль',
          moneyCompact(s.profit),
          s.profitDelta,
          Icons.account_balance_wallet_outlined,
          AppColors.fresh,
          hint: 'маржа ${s.margin.toStringAsFixed(1).replaceAll('.', ',')}%',
        ),
      _Kpi(
        'Заказы',
        NumberFormat.decimalPattern('ru').format(s.orders),
        s.ordersDelta,
        Icons.receipt_long_outlined,
        AppColors.hit,
      ),
      _Kpi(
        'Средний чек',
        money.format(s.avgCheck),
        s.avgCheckDelta,
        Icons.shopping_basket_outlined,
        AppColors.wholesale,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
        final w = (c.maxWidth - Insets.lg * (cols - 1)) / cols;
        return Wrap(
          spacing: Insets.lg,
          runSpacing: Insets.lg,
          children: [for (final k in cards) SizedBox(width: w, child: k)],
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(
    this.label,
    this.value,
    this.delta,
    this.icon,
    this.color, {
    this.hint,
  });
  final String label;
  final String value;
  final double delta;
  final IconData icon;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AdminCard(
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              DeltaChip(delta),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Text(
            label,
            style: text.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint ?? 'к прошлому периоду',
            style: text.labelSmall?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueChartCard extends ConsumerWidget {
  const _RevenueChartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(periodStatsProvider).current;
    final text = Theme.of(context).textTheme;
    // max(…, 1): пока данные с сервера не пришли, дней 0 — нулевой шаг уронил бы график (0 ~/ 0)
    final step = math.max((days.length / 7).ceil(), 1);
    if (days.isEmpty) {
      return const AdminCard(
        title: 'Выручка и прибыль',
        child: SizedBox(
          height: 280,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    LineChartBarData line(
      double Function(DayFinance) pick,
      Color color, {
      bool fill = true,
    }) => LineChartBarData(
      spots: [for (final (i, d) in days.indexed) FlSpot(i.toDouble(), pick(d))],
      isCurved: true,
      curveSmoothness: 0.3,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 3,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: fill,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ),
      ),
    );

    // Без права finance:view сервер не отдаёт расходы — показываем только выручку
    final showProfit = ref.watch(profitVisibleProvider);
    return AdminCard(
      title: showProfit ? 'Выручка и прибыль' : 'Выручка',
      subtitle: 'По дням, ₽',
      action: Wrap(
        spacing: Insets.md,
        children: [
          const _Legend('Выручка', AppColors.brand),
          if (showProfit) ...const [
            _Legend('Расходы', AppColors.hit),
            _Legend('Прибыль', AppColors.fresh),
          ],
        ],
      ),
      child: SizedBox(
        height: 280,
        child: LineChart(
          duration: const Duration(milliseconds: 400),
          LineChartData(
            minY: 0,
            // Новый магазин: за период одни нули — без явного максимума у шкалы нулевой шаг и график падает
            maxY: days.every((d) => d.revenue <= 0 && d.expenses <= 0)
                ? 1000
                : null,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: context.palette.border,
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => context.palette.textPrimary,
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      money.format(s.y),
                      TextStyle(
                        color: s.bar.color,
                        fontWeight: FontWeight.w700,
                      ),
                      children: [
                        if (s == spots.first)
                          TextSpan(
                            text:
                                '\n${DateFormat('d MMM', 'ru').format(days[s.x.toInt()].day)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w400,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 52,
                  getTitlesWidget: (v, meta) => v == meta.max
                      ? const SizedBox()
                      : Text(
                          _compactAxis(v),
                          style: text.labelSmall?.copyWith(
                            color: context.palette.textSecondary,
                          ),
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: step.toDouble(),
                  reservedSize: 28,
                  getTitlesWidget: (v, _) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat('d MMM', 'ru').format(days[v.toInt()].day),
                      style: text.labelSmall?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            lineBarsData: [
              line((d) => d.revenue, AppColors.brand),
              if (showProfit) ...[
                line((d) => d.expenses, AppColors.hit, fill: false),
                line((d) => d.profit, AppColors.fresh),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _compactAxis(double v) =>
      v >= 1000 ? '${(v / 1000).round()}k' : v.round().toString();
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

class _OrdersByStageCard extends ConsumerWidget {
  const _OrdersByStageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(adminOrdersProvider);
    final counts = {
      for (final s in OrderStage.values)
        s: orders.where((o) => o.stage == s).length,
    };
    final text = Theme.of(context).textTheme;

    return AdminCard(
      title: 'Статусы заказов',
      subtitle: 'Последние ${orders.length} заказов',
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 58,
                    sectionsSpace: 3,
                    sections: [
                      for (final MapEntry(key: s, value: n) in counts.entries)
                        if (n > 0)
                          PieChartSectionData(
                            value: n.toDouble(),
                            color: s.color,
                            radius: 22,
                            showTitle: false,
                          ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${orders.length}',
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'заказов',
                      style: text.labelMedium?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),
          for (final MapEntry(key: s, value: n) in counts.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(child: Text(s.label)),
                  Text(
                    '$n',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentOrdersCard extends ConsumerWidget {
  const _RecentOrdersCard({this.onOpenOrders});
  final VoidCallback? onOpenOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(adminOrdersProvider).take(6).toList();
    final text = Theme.of(context).textTheme;
    return AdminCard(
      title: 'Последние заказы',
      action: onOpenOrders == null
          ? null
          : TextButton(
              onPressed: onOpenOrders,
              child: const Text('Все заказы →'),
            ),
      child: Column(
        children: [
          for (final (i, o) in orders.indexed) ...[
            if (i > 0) const Divider(height: Insets.lg),
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: o.stage.color.withValues(alpha: 0.12),
                  child: Icon(o.stage.icon, size: 18, color: o.stage.color),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${o.number} · ${o.customer}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${o.itemsCount} шт. · ${timeAgo(o.createdAt)}',
                        style: text.bodySmall?.copyWith(
                          color: context.palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money.format(o.total),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    StageChip(o.stage),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TopProductsCard extends ConsumerWidget {
  const _TopProductsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(topProductsProvider);
    final maxRevenue = top.isEmpty ? 1.0 : top.first.revenue;
    final text = Theme.of(context).textTheme;
    return AdminCard(
      title: 'Топ товаров',
      subtitle: 'По выручке',
      child: Column(
        children: [
          for (final (i, (:name, :imageUrl, :qty, :revenue))
              in top.indexed) ...[
            if (i > 0) const SizedBox(height: Insets.lg),
            Row(
              children: [
                ProductThumb(imageUrl),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            money.format(revenue),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Radii.pill),
                              child: LinearProgressIndicator(
                                value: revenue / maxRevenue,
                                minHeight: 6,
                                backgroundColor: context.palette.background,
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColors.brand,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: Insets.sm),
                          Text(
                            '$qty шт.',
                            style: text.labelSmall?.copyWith(
                              color: context.palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LowStockCard extends ConsumerWidget {
  const _LowStockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(lowStockProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    return AdminCard(
      title: 'Заканчиваются',
      subtitle: 'Остаток 5 шт. и меньше — пора заказать у поставщика',
      action: const Icon(Icons.warning_amber_rounded, color: AppColors.hit),
      child: Wrap(
        spacing: Insets.md,
        runSpacing: Insets.md,
        children: [
          for (final i in items)
            Container(
              width: 240,
              padding: const EdgeInsets.all(Insets.sm),
              decoration: BoxDecoration(
                border: Border.all(color: context.palette.border),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                children: [
                  ProductThumb(i.imageUrl, size: 40),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Text(
                      i.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.lowStock.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      '${i.stock} шт.',
                      style: const TextStyle(
                        color: AppColors.lowStock,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DeliveryZoneBanner extends ConsumerWidget {
  const _DeliveryZoneBanner({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = ref.watch(deliveryZoneProvider).value;
    final summary = zone == null
        ? 'Загружаем…'
        : !zone.enabled
        ? 'Ограничение выключено — принимаем любые адреса'
        : 'Радиус ${zone.radiusKm.toStringAsFixed(0)} км от «${zone.storeAddress}»'
              '${zone.cities.isEmpty ? '' : ' + города: ${zone.cities.join(', ')}'}';
    return Material(
      color: AppColors.brand.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(Radii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                const Icon(Icons.map_rounded, color: AppColors.brand),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Зона доставки',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.palette.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.md),
                if (box.maxWidth < 480)
                  IconButton.filledTonal(
                    tooltip: 'Изменить радиус',
                    onPressed: onOpen,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: const Text('Изменить радиус'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
