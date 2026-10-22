import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/chat_panel.dart';
import '../../../core/widgets/app_image.dart';
import '../../catalog/presentation/providers/catalog_filter.dart';
import '../../catalog/presentation/providers/shop_providers.dart';
import '../../catalog/presentation/widgets/price_tag.dart';
import '../customer_session.dart';
import '../data/account_api.dart';

Color orderStateColor(BuildContext context, OrderState s) => switch (s) {
  OrderState.delivered => AppColors.fresh,
  OrderState.cancelled => context.palette.textSecondary,
  OrderState.shipped => AppColors.wholesale,
  _ => AppColors.hit,
};

class OrderStateChip extends StatelessWidget {
  const OrderStateChip(this.state, {super.key});
  final OrderState state;

  @override
  Widget build(BuildContext context) {
    final color = orderStateColor(context, state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        state.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

Future<void> showOrderDetails(BuildContext context, CustomerOrder order) {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  final body = OrderDetailsView(order: order);
  if (!wide) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.92, child: body),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Закрыть',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: context.palette.surface,
        elevation: 12,
        child: SizedBox(
          width: 520,
          height: double.infinity,
          child: SafeArea(child: body),
        ),
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

class OrderDetailsView extends ConsumerWidget {
  const OrderDetailsView({super.key, required this.order});
  final CustomerOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final goods = order.lines.fold(0.0, (a, l) => a + l.total);

    Widget row(String l, String v, {bool bold = false, Color? color}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l,
                  style: TextStyle(
                    color: bold ? null : context.palette.textSecondary,
                  ),
                ),
              ),
              Text(
                v,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontSize: bold ? 17 : null,
                  color: color,
                ),
              ),
            ],
          ),
        );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              Insets.md,
              Insets.xl,
              Insets.lg,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Заказ ${order.number}',
                      style: text.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                '${DateFormat('d MMMM yyyy, HH:mm', 'ru').format(order.createdAt)} · ${order.deliveryLabel}',
                style: TextStyle(color: context.palette.textSecondary),
              ),
              const SizedBox(height: Insets.xl),
              _StatusSteps(state: order.state),
              const SizedBox(height: Insets.xl),
              Text(
                'Состав · ${order.itemsCount} шт.',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Insets.md),
              for (final l in order.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: context.palette.surfaceMuted,
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: l.imageUrl == null
                            ? null
                            : AppImage(
                                imageUrl: l.imageUrl!,
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
                              l.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${l.qty} × ${rub.format(l.price)}${l.unit == null ? '' : ' · ${l.unit}'}',
                              style: TextStyle(
                                color: context.palette.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        rub.format(l.total),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              const Divider(height: Insets.xl),
              row('Товары', rub.format(goods)),
              row(
                'Доставка',
                order.deliveryFee == 0
                    ? 'Бесплатно'
                    : rub.format(order.deliveryFee),
                color: order.deliveryFee == 0 ? AppColors.fresh : null,
              ),
              if ((goods + order.deliveryFee - order.total).abs() > 0.5)
                row(
                  'Скидки',
                  '−${rub.format(goods + order.deliveryFee - order.total)}',
                  color: AppColors.lowStock,
                ),
              row('Итого', rub.format(order.total), bold: true),
              const SizedBox(height: 4),
              Text(
                order.paymentLabel,
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: Insets.lg),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  if (order.awaitingPayment && !order.state.isClosed)
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          final url = await ref
                              .read(accountApiProvider)
                              .payAgain(order.id);
                          await launchUrl(
                            Uri.parse(url),
                            webOnlyWindowName: '_self',
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                      icon: const Icon(Icons.credit_card_rounded, size: 18),
                      label: Text('Оплатить ${rub.format(order.total)}'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => repeatOrder(context, ref, order),
                    icon: const Icon(Icons.replay_rounded, size: 18),
                    label: const Text('Повторить заказ'),
                  ),
                ],
              ),
              if (order.state == OrderState.shipped) ...[
                const SizedBox(height: Insets.xl),
                _CourierBlock(orderId: order.id),
              ],
              const SizedBox(height: Insets.xl),
              Text(
                'Переписка по заказу',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Insets.sm),
              _CommentsThread(orderId: order.id),
            ],
          ),
        ),
        if (!order.state.isClosed) _CommentComposer(orderId: order.id),
      ],
    );
  }
}

final _courierProvider = FutureProvider.autoDispose.family<CourierInfo, int>(
  (ref, id) => ref.read(accountApiProvider).courier(id),
);

/// Курьер и чат с ним. Телефонами стороны не обмениваются: номер покупателя курьер
/// увидит только рядом с адресом или по кнопке «ЧП» (с причиной, о которой узнаете здесь).
class _CourierBlock extends ConsumerWidget {
  const _CourierBlock({required this.orderId});
  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(_courierProvider(orderId)).value;
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    if (info == null) return const SizedBox.shrink();
    if (!info.assigned) {
      return Row(
        children: [
          Icon(Icons.delivery_dining_outlined, color: palette.textSecondary),
          const SizedBox(width: Insets.sm),
          const Expanded(
            child: Text('Заказ передан в доставку, назначаем курьера'),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.brand.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.delivery_dining_rounded,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Курьер ${info.name}',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      info.distanceKm == null
                          ? 'Везёт ваш заказ'
                          : 'Примерно ${info.distanceKm!.toStringAsFixed(1)} км до вас',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Icon(
                info.phoneOpened
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
                size: 16,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  info.phoneOpened
                      ? 'Курьеру открыт ваш номер: ${info.phoneRevealReason ?? 'он рядом'}'
                      : 'Ваш номер скрыт от курьера — он увидит его, только подъехав к адресу',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          const Divider(height: Insets.xl),
          ChatPanel(
            mineIsStaff: false,
            hint: 'Написать курьеру…',
            emptyText: 'Напишите курьеру код домофона или как вас найти',
            quickReplies: const [
              'Код домофона: ',
              'Я дома, жду',
              'Оставьте у двери',
            ],
            load: () => ref.read(accountApiProvider).courierChat(orderId),
            send: (t) => ref.read(accountApiProvider).courierSay(orderId, t),
          ),
        ],
      ),
    );
  }
}

/// «Повторить заказ»: всё, что ещё продаётся, — в корзину одним нажатием.
void repeatOrder(BuildContext context, WidgetRef ref, CustomerOrder order) {
  final byId = {for (final p in ref.read(allProductsProvider)) p.id: p};
  var added = 0, missing = 0;
  for (final l in order.lines) {
    final p = byId[l.productId];
    if (p == null || !p.inStock) {
      missing++;
      continue;
    }
    ref.read(cartProvider.notifier).add(p, l.qty);
    added += l.qty;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        missing == 0
            ? 'В корзину добавлено $added шт.'
            : 'Добавлено $added шт., $missing позиций сейчас нет в наличии',
      ),
    ),
  );
}

class _StatusSteps extends StatelessWidget {
  const _StatusSteps({required this.state});
  final OrderState state;

  static const _steps = [
    OrderState.newOrder,
    OrderState.picking,
    OrderState.shipped,
    OrderState.delivered,
  ];
  static const _icons = [
    Icons.receipt_long_rounded,
    Icons.inventory_2_rounded,
    Icons.local_shipping_rounded,
    Icons.home_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    if (state == OrderState.cancelled) {
      return Container(
        padding: const EdgeInsets.all(Insets.md),
        decoration: BoxDecoration(
          color: context.palette.surfaceMuted,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            Icon(Icons.cancel_outlined, color: context.palette.textSecondary),
            const SizedBox(width: Insets.sm),
            const Expanded(
              child: Text(
                'Заказ отменён. Если деньги были списаны, они вернутся на карту.',
              ),
            ),
          ],
        ),
      );
    }
    final current = _steps.indexOf(state);
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: i <= current
                      ? AppColors.fresh
                      : context.palette.surfaceMuted,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _icons[i],
                  size: 18,
                  color: i <= current
                      ? Colors.white
                      : context.palette.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _steps[i].label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                  color: i <= current ? null : context.palette.textSecondary,
                ),
              ),
            ],
          ),
          if (i < _steps.length - 1)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.only(bottom: 18),
                color: i < current ? AppColors.fresh : context.palette.border,
              ),
            ),
        ],
      ],
    );
  }
}

class _CommentsThread extends ConsumerWidget {
  const _CommentsThread({required this.orderId});
  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(orderCommentsProvider(orderId));
    return switch (comments) {
      AsyncData(:final value) when value.isEmpty => Text(
        'Напишите, если нужно что-то уточнить: позвонить заранее, заменить товар, оставить у двери.',
        style: TextStyle(color: context.palette.textSecondary),
      ),
      AsyncData(:final value) => Column(
        children: [for (final m in value) ChatBubble(message: m)],
      ),
      AsyncError(:final error) => Text(
        '$error',
        style: const TextStyle(color: AppColors.lowStock),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(Insets.md),
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.mineIsStaff = false,
  });
  final OrderMessage message;
  final bool mineIsStaff; // в админке «свои» — сообщения магазина

  @override
  Widget build(BuildContext context) {
    final mine = message.fromStaff == mineIsStaff;
    final bg = mine ? AppColors.brand : context.palette.surfaceMuted;
    final fg = mine ? Colors.white : context.palette.textPrimary;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.only(bottom: Insets.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(Radii.md),
            topRight: const Radius.circular(Radii.md),
            bottomLeft: Radius.circular(mine ? Radii.md : 4),
            bottomRight: Radius.circular(mine ? 4 : Radii.md),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                message.author,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            Text(message.text, style: TextStyle(color: fg)),
            const SizedBox(height: 2),
            Text(
              DateFormat('d MMM, HH:mm', 'ru').format(message.createdAt),
              style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentComposer extends ConsumerStatefulWidget {
  const _CommentComposer({required this.orderId});
  final int orderId;

  @override
  ConsumerState<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends ConsumerState<_CommentComposer> {
  final _text = TextEditingController();
  bool _busy = false;

  static const _quick = [
    'Позвоните за 30 минут',
    'Оставьте у двери',
    'Можно заменить на аналог',
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final msg = (preset ?? _text.text).trim();
    if (msg.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(accountApiProvider).addComment(widget.orderId, msg);
      _text.clear();
      ref.invalidate(orderCommentsProvider(widget.orderId));
      // В демо магазин «отвечает» через пару секунд — подтягиваем ответ
      Future<void>.delayed(const Duration(milliseconds: 2300), () {
        if (mounted) ref.invalidate(orderCommentsProvider(widget.orderId));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.lg,
        Insets.md,
      ),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final q in _quick)
                    Padding(
                      padding: const EdgeInsets.only(right: Insets.sm),
                      child: ActionChip(
                        label: Text(q),
                        onPressed: () => _send(q),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Комментарий к заказу…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                IconButton.filled(
                  tooltip: 'Отправить',
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
