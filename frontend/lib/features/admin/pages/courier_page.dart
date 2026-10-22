import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/chat_panel.dart';
import '../data/admin_data.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

/// Экран курьера (удобно с телефона): свободные и мои заказы в пути.
/// Телефон покупателя скрыт, пока курьер не ближе 1 км к адресу (или не нажал «ЧП»).
class CourierPage extends ConsumerWidget {
  const CourierPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(courierOrdersProvider);
    final mine = [
      for (final o in orders)
        if (o.mine) o,
    ];
    final free = [
      for (final o in orders)
        if (!o.mine) o,
    ];
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: ref.read(courierOrdersProvider.notifier).reload,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            EmptyState(
              icon: Icons.delivery_dining_outlined,
              title: 'Заказов в пути нет',
              subtitle:
                  'Когда сборщик передаст заказ в доставку, он появится здесь',
            ),
          ],
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: ref.read(courierOrdersProvider.notifier).reload,
      child: LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 1100 ? 2 : 1;
          final w =
              (c.maxWidth - Insets.xl * 2 - Insets.lg * (cols - 1)) / cols;
          Widget group(String title, List<CourierOrder> list) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Insets.md),
              Wrap(
                spacing: Insets.lg,
                runSpacing: Insets.lg,
                children: [
                  for (final o in list)
                    SizedBox(
                      width: w,
                      child: _CourierCard(order: o),
                    ),
                ],
              ),
              const SizedBox(height: Insets.xl),
            ],
          );
          return ListView(
            padding: const EdgeInsets.all(Insets.xl),
            children: [
              if (mine.isNotEmpty) group('Везу сейчас · ${mine.length}', mine),
              if (free.isNotEmpty) group('Можно взять · ${free.length}', free),
            ],
          );
        },
      ),
    );
  }
}

class _CourierCard extends ConsumerStatefulWidget {
  const _CourierCard({required this.order});
  final CourierOrder order;

  @override
  ConsumerState<_CourierCard> createState() => _CourierCardState();
}

class _CourierCardState extends ConsumerState<_CourierCard> {
  bool _busy = false;

  CourierOrder get o => widget.order;
  CourierOrdersNotifier get _n => ref.read(courierOrdersProvider.notifier);

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Геопозиция: в демо курьер «подъезжает» на 40% пути за нажатие, в релизе — GPS браузера.
  Future<void> _locate() => _run(() async {
    final repo = ref.read(adminRepositoryProvider);
    if (AppConfig.isDemo && repo is DemoAdminRepository) {
      final (lat, lng) = repo.demoNextPosition(o.id);
      return _n.locate(o.id, lat, lng);
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Разрешите доступ к геопозиции в браузере — без неё номер откроется только по ЧП',
            ),
          ),
        );
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      await _n.locate(o.id, p.latitude, p.longitude);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось определить местоположение: $e')),
      );
    }
  });

  Future<void> _emergency() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _EmergencyDialog(),
    );
    if (reason != null) await _run(() => _n.emergency(o.id, reason));
  }

  Future<void> _deliver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Заказ ${o.number} вручён?'),
        content: Text(
          o.cashToCollect == null
              ? 'Заказ оплачен онлайн — деньги брать не нужно.'
              : 'Убедитесь, что получили оплату: ${money.format(o.cashToCollect)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Да, вручён'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _n.delivered(o.id));
  }

  void _openChat() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(
        Insets.xl,
        0,
        Insets.xl,
        Insets.xl + MediaQuery.viewInsetsOf(c).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Чат с покупателем · ${o.customerName}',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Телефоны в чате не видны ни вам, ни покупателю',
              style: TextStyle(color: c.palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Insets.md),
            ChatPanel(
              mineIsStaff: true,
              hint: 'Написать покупателю…',
              emptyText:
                  'Напишите покупателю, если нужно уточнить адрес или время',
              quickReplies: const [
                'Выехал к вам',
                'Буду через 10 минут',
                'Я у подъезда',
                'Не могу найти вход — подскажите?',
              ],
              load: () => ref.read(adminRepositoryProvider).courierChat(o.id),
              send: (t) =>
                  ref.read(adminRepositoryProvider).courierSay(o.id, t),
            ),
          ],
        ),
      ),
    ),
  );

  Uri get _route => o.destLat != null
      ? Uri.parse(
          'https://yandex.ru/maps/?rtext=~${o.destLat},${o.destLng}&rtt=auto',
        )
      : Uri.parse(
          'https://yandex.ru/maps/?text=${Uri.encodeComponent(o.address)}',
        );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return AdminCard(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${o.number} · ${o.customerName}',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (o.distanceKm != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    '${o.distanceKm!.toStringAsFixed(1)} км',
                    style: const TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.place_outlined,
                size: 18,
                color: palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(o.address)),
              TextButton.icon(
                onPressed: () =>
                    launchUrl(_route, mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.navigation_outlined, size: 18),
                label: const Text('Маршрут'),
              ),
            ],
          ),
          if (o.note != null) ...[
            const SizedBox(height: 6),
            Text(
              '«${o.note}»',
              style: TextStyle(
                color: palette.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: Insets.sm,
            runSpacing: 6,
            children: [
              Chip(
                avatar: const Icon(Icons.shopping_bag_outlined, size: 16),
                label: Text('${o.itemsCount} шт.'),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                avatar: Icon(
                  o.cashToCollect == null
                      ? Icons.credit_card_rounded
                      : Icons.payments_outlined,
                  size: 16,
                  color: o.cashToCollect == null
                      ? AppColors.fresh
                      : AppColors.hit,
                ),
                label: Text(
                  o.cashToCollect == null
                      ? 'Оплачен онлайн'
                      : 'Взять ${money.format(o.cashToCollect)}',
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (o.mine) ...[
            const SizedBox(height: Insets.sm),
            _PhoneRow(order: o),
          ],
          const SizedBox(height: Insets.md),
          if (!o.mine)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy ? null : () => _run(() => _n.take(o.id)),
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('Взять заказ'),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: _busy ? null : _locate,
                    icon: const Icon(Icons.my_location_rounded),
                    label: Text(
                      AppConfig.isDemo ? 'Подъехать (демо)' : 'Моя геопозиция',
                    ),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: _openChat,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Чат'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppColors.fresh,
              ),
              onPressed: _busy ? null : _deliver,
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Вручён'),
            ),
            if (o.phone == null)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.lowStock,
                ),
                onPressed: _busy ? null : _emergency,
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('ЧП — нужен телефон покупателя'),
              ),
          ],
        ],
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.order});
  final CourierOrder order;

  @override
  Widget build(BuildContext context) {
    final phone = order.phone;
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: (phone == null
            ? palette.background
            : AppColors.fresh.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        children: [
          Icon(
            phone == null ? Icons.lock_outline_rounded : Icons.phone_rounded,
            color: phone == null ? palette.textSecondary : AppColors.fresh,
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phone ?? order.phoneMasked,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  phone == null
                      ? 'Номер откроется, когда вы будете ближе 1 км к адресу. Пока — чат.'
                      : order.phoneRevealReason ?? 'Номер открыт',
                  style: TextStyle(color: palette.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (phone != null)
            IconButton.filledTonal(
              tooltip: 'Позвонить',
              onPressed: () => launchUrl(
                Uri(
                  scheme: 'tel',
                  path: phone.replaceAll(RegExp(r'[^\d+]'), ''),
                ),
              ),
              icon: const Icon(Icons.call_rounded),
            ),
        ],
      ),
    );
  }
}

class _EmergencyDialog extends StatefulWidget {
  const _EmergencyDialog();

  @override
  State<_EmergencyDialog> createState() => _EmergencyDialogState();
}

class _EmergencyDialogState extends State<_EmergencyDialog> {
  static const _reasons = [
    'Покупатель не отвечает в чате',
    'Не могу попасть в подъезд, домофон не работает',
    'Не могу найти адрес',
    'Опаздываю больше чем на 30 минут',
    'Проблема с заказом (повреждён товар)',
  ];
  String? _picked;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String get _reason => _picked == null ? _other.text.trim() : _picked!;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(
      Icons.warning_amber_rounded,
      color: AppColors.lowStock,
      size: 36,
    ),
    title: const Text('Открыть телефон покупателя?'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Используйте, только если связаться через чат не получается. '
            'Покупатель и магазин увидят причину.',
          ),
          const SizedBox(height: Insets.md),
          RadioGroup<String?>(
            groupValue: _picked,
            onChanged: (v) => setState(() => _picked = v),
            child: Column(
              children: [
                for (final r in _reasons)
                  RadioListTile<String?>(
                    value: r,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r),
                  ),
                const RadioListTile<String?>(
                  value: null,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Другое'),
                ),
              ],
            ),
          ),
          if (_picked == null)
            TextField(
              controller: _other,
              onChanged: (_) => setState(() {}),
              maxLength: 280,
              decoration: const InputDecoration(hintText: 'Опишите ситуацию'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: AppColors.lowStock),
        onPressed: _reason.length >= 5
            ? () => Navigator.pop(context, _reason)
            : null,
        child: const Text('Открыть номер'),
      ),
    ],
  );
}
