import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../account/presentation/order_details.dart' show ChatBubble;
import '../data/admin_data.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

class _StageFilter extends Notifier<OrderStage?> {
  @override
  OrderStage? build() => null;
  void set(OrderStage? s) => state = s;
}

final _stageFilterProvider = NotifierProvider<_StageFilter, OrderStage?>(
  _StageFilter.new,
);

class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(adminOrdersProvider);
    final filter = ref.watch(_stageFilterProvider);
    final orders = filter == null
        ? all
        : all.where((o) => o.stage == filter).toList();

    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            ChoiceChip(
              label: Text('Все · ${all.length}'),
              selected: filter == null,
              onSelected: (_) =>
                  ref.read(_stageFilterProvider.notifier).set(null),
            ),
            for (final s in OrderStage.values)
              ChoiceChip(
                avatar: Icon(s.icon, size: 16, color: s.color),
                label: Text(
                  '${s.label} · ${all.where((o) => o.stage == s).length}',
                ),
                selected: filter == s,
                onSelected: (_) => ref
                    .read(_stageFilterProvider.notifier)
                    .set(filter == s ? null : s),
              ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        AdminCard(
          padding: EdgeInsets.zero,
          child: orders.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Заказов с этим статусом нет',
                )
              : LayoutBuilder(
                  builder: (context, c) => c.maxWidth >= 980
                      ? _OrdersTable(orders: orders)
                      : Column(
                          children: [
                            for (final o in orders) _OrderTile(order: o),
                          ],
                        ),
                ),
        ),
      ],
    );
  }
}

class _OrdersTable extends StatelessWidget {
  const _OrdersTable({required this.orders});
  final List<AdminOrder> orders;

  @override
  Widget build(BuildContext context) {
    final head = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: context.palette.textSecondary,
      fontWeight: FontWeight.w600,
    );
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.xl,
            vertical: Insets.md,
          ),
          decoration: BoxDecoration(
            color: context.palette.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
          ),
          child: Row(
            children: [
              SizedBox(width: 90, child: Text('ЗАКАЗ', style: head)),
              Expanded(flex: 3, child: Text('КЛИЕНТ', style: head)),
              Expanded(flex: 2, child: Text('СОЗДАН', style: head)),
              SizedBox(width: 70, child: Text('ТОВАРЫ', style: head)),
              SizedBox(
                width: 110,
                child: Text('СУММА', style: head, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 110,
                child: Text('ПРИБЫЛЬ', style: head, textAlign: TextAlign.right),
              ),
              const SizedBox(width: Insets.xl),
              SizedBox(width: 170, child: Text('ОПЛАТА', style: head)),
              SizedBox(width: 120, child: Text('СТАТУС', style: head)),
            ],
          ),
        ),
        for (final (i, o) in orders.indexed) ...[
          if (i > 0) const Divider(),
          InkWell(
            onTap: () => showOrderDetails(context, o.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.xl,
                vertical: Insets.md,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      o.number,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            o.customer,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (o.isB2B) ...[
                          const SizedBox(width: 6),
                          const _B2BBadge(),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      timeAgo(o.createdAt),
                      style: TextStyle(color: context.palette.textSecondary),
                    ),
                  ),
                  SizedBox(width: 70, child: Text('${o.itemsCount} шт.')),
                  SizedBox(
                    width: 110,
                    child: Text(
                      money.format(o.total),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(
                      money.format(o.profit),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: o.profit >= 0
                            ? AppColors.fresh
                            : AppColors.lowStock,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.xl),
                  SizedBox(
                    width: 170,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: PaymentChip(o.payment),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: StageChip(o.stage),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});
  final AdminOrder order;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => showOrderDetails(context, order.id),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: 4,
      ),
      leading: CircleAvatar(
        backgroundColor: order.stage.color.withValues(alpha: 0.12),
        child: Icon(order.stage.icon, color: order.stage.color, size: 20),
      ),
      title: Text(
        '${order.number} · ${order.customer}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${order.itemsCount} шт. · ${timeAgo(order.createdAt)} · ${order.payment.label}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            money.format(order.total),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          StageChip(order.stage),
        ],
      ),
    );
  }
}

class _B2BBadge extends StatelessWidget {
  const _B2BBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.wholesale.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Text(
      'B2B',
      style: TextStyle(
        color: AppColors.wholesale,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

Future<void> showOrderDetails(BuildContext context, int orderId) {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  final body = _OrderDetails(orderId: orderId);
  if (wide) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Закрыть',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: context.palette.surface,
          elevation: 12,
          child: SizedBox(width: 460, height: double.infinity, child: body),
        ),
      ),
      transitionBuilder: (_, a, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.palette.surface,
    builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: body),
  );
}

class _OrderDetails extends ConsumerWidget {
  const _OrderDetails({required this.orderId});
  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(adminOrdersProvider).firstWhere((x) => x.id == orderId);
    final text = Theme.of(context).textTheme;

    Widget row(String l, String v, {Color? color, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l,
                  style: TextStyle(color: context.palette.textSecondary),
                ),
              ),
              Text(
                v,
                style: TextStyle(
                  color: color,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        Row(
          children: [
            Text('Заказ ${o.number}', style: text.titleLarge),
            const SizedBox(width: Insets.md),
            StageChip(o.stage),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: Insets.sm,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              timeAgo(o.createdAt),
              style: TextStyle(color: context.palette.textSecondary),
            ),
            PaymentChip(o.payment),
          ],
        ),
        const SizedBox(height: Insets.xl),
        _InfoBlock(
          icon: Icons.person_outline_rounded,
          title: o.customer,
          subtitle: o.isB2B
              ? 'B2B-клиент · оптовый прайс'
              : 'Розничный покупатель',
        ),
        _InfoBlock(
          icon: Icons.place_outlined,
          title: o.address,
          subtitle: 'Москва',
        ),
        if (o.comment != null)
          _InfoBlock(
            icon: Icons.chat_bubble_outline_rounded,
            title: o.comment!,
            subtitle: 'Комментарий клиента',
          ),
        const SizedBox(height: Insets.lg),
        Text(
          'Состав · ${o.itemsCount} шт.',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Insets.md),
        for (final l in o.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md),
            child: Row(
              children: [
                ProductThumb(l.imageUrl, size: 40),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    '${l.name}\n${l.unit ?? 'шт.'} × ${l.qty}',
                    style: const TextStyle(height: 1.3),
                  ),
                ),
                Text(
                  money.format(l.total),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        const Divider(height: Insets.xl),
        row('Сумма заказа', money.format(o.total), bold: true),
        row('Себестоимость', '−${money.format(o.cost)}'),
        row('Доставка (наши расходы)', '−${money.format(o.delivery)}'),
        row(
          'Чистая прибыль',
          '${money.format(o.profit)} · ${(o.profit / o.total * 100).toStringAsFixed(0)}%',
          color: o.profit >= 0 ? AppColors.fresh : AppColors.lowStock,
          bold: true,
        ),
        const SizedBox(height: Insets.xl),
        Text(
          'Переписка с покупателем',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Insets.sm),
        _AdminThread(orderId: o.id, closed: o.stage.next.isEmpty),
        const SizedBox(height: Insets.xl),
        if (o.stage.next.isNotEmpty) ...[
          Text(
            'Сменить статус',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final s in o.stage.next)
                s == OrderStage.cancelled
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.lowStock,
                        ),
                        onPressed: () => ref
                            .read(adminOrdersProvider.notifier)
                            .setStage(o.id, s),
                        icon: Icon(s.icon, size: 18),
                        label: const Text('Отменить'),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: s.color),
                        onPressed: () => ref
                            .read(adminOrdersProvider.notifier)
                            .setStage(o.id, s),
                        icon: Icon(s.icon, size: 18),
                        label: Text('→ ${s.label}'),
                      ),
            ],
          ),
        ] else
          Text(
            'Заказ закрыт',
            style: text.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Insets.md),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: context.palette.background,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Icon(icon, size: 18),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AdminThread extends ConsumerStatefulWidget {
  const _AdminThread({required this.orderId, required this.closed});
  final int orderId;
  final bool closed;

  @override
  ConsumerState<_AdminThread> createState() => _AdminThreadState();
}

class _AdminThreadState extends ConsumerState<_AdminThread> {
  final _text = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final msg = _text.text.trim();
    if (msg.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).replyToOrder(widget.orderId, msg);
      _text.clear();
      ref.invalidate(adminOrderCommentsProvider(widget.orderId));
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(adminOrderCommentsProvider(widget.orderId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (thread) {
          AsyncData(:final value) when value.isEmpty => Text(
            'Сообщений нет',
            style: TextStyle(color: context.palette.textSecondary),
          ),
          AsyncData(:final value) => Column(
            children: [
              for (final m in value) ChatBubble(message: m, mineIsStaff: true),
            ],
          ),
          AsyncError(:final error) => Text(
            '$error',
            style: const TextStyle(color: AppColors.lowStock),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
        if (!widget.closed) ...[
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 3,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Ответить покупателю…',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: Insets.sm),
              IconButton.filled(
                tooltip: 'Отправить',
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
