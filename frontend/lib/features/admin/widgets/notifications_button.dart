import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../data/admin_data.dart';
import '../rbac.dart';

typedef _Item = ({AdminSection section, IconData icon, String text, int count});

/// Колокольчик: что ждёт реакции — новые заказы, обращения, отзывы, заявки компаний.
class NotificationsButton extends ConsumerStatefulWidget {
  const NotificationsButton({super.key, required this.onOpen});
  final ValueChanged<AdminSection> onOpen;

  @override
  ConsumerState<NotificationsButton> createState() =>
      _NotificationsButtonState();
}

class _NotificationsButtonState extends ConsumerState<NotificationsButton> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // в релизе подтягиваем свежее раз в минуту — новый заказ или вопрос не ждёт перезагрузки страницы
    if (!AppConfig.isDemo) {
      _poll = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _refresh() {
    final sections = ref.read(visibleSectionsProvider);
    if (sections.contains(AdminSection.orders) ||
        sections.contains(AdminSection.picking)) {
      ref.read(adminOrdersProvider.notifier).reload();
    }
    if (sections.contains(AdminSection.support)) {
      ref.read(supportThreadsProvider.notifier).reload();
    }
  }

  List<_Item> _items(List<AdminSection> sections) {
    final items = <_Item>[];
    if (sections.contains(AdminSection.orders) ||
        sections.contains(AdminSection.picking)) {
      final n = ref.watch(
        adminOrdersProvider.select(
          (o) => o.where((x) => x.stage == OrderStage.newOrder).length,
        ),
      );
      items.add((
        section: sections.contains(AdminSection.orders)
            ? AdminSection.orders
            : AdminSection.picking,
        icon: Icons.receipt_long_outlined,
        text: 'Новые заказы',
        count: n,
      ));
    }
    if (sections.contains(AdminSection.support)) {
      items.add((
        section: AdminSection.support,
        icon: Icons.support_agent_outlined,
        text: 'Вопросы в поддержке',
        count: ref.watch(supportUnreadProvider),
      ));
    }
    if (sections.contains(AdminSection.reviews)) {
      items.add((
        section: AdminSection.reviews,
        icon: Icons.rate_review_outlined,
        text: 'Отзывы на модерации',
        count: ref.watch(
          reviewsProvider.select(
            (r) => r.where((x) => x.state == ReviewState.pending).length,
          ),
        ),
      ));
    }
    if (sections.contains(AdminSection.business)) {
      items.add((
        section: AdminSection.business,
        icon: Icons.storefront_outlined,
        text: 'Заявки компаний',
        count: ref.watch(
          companiesProvider.select(
            (c) => c.where((x) => x.status == B2BStatus.pending).length,
          ),
        ),
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(ref.watch(visibleSectionsProvider));
    final total = items.fold(0, (sum, i) => sum + i.count);
    final muted = TextStyle(color: context.palette.textSecondary);
    return MenuAnchor(
      alignmentOffset: const Offset(-220, 8),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            total == 0 ? 'Всё обработано' : 'Ждут вашего внимания',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        for (final i in items)
          MenuItemButton(
            leadingIcon: Icon(i.icon, size: 20),
            trailingIcon: i.count > 0
                ? Badge.count(
                    count: i.count,
                    backgroundColor: AppColors.lowStock,
                  )
                : Text('0', style: muted),
            onPressed: () => widget.onOpen(i.section),
            child: SizedBox(width: 200, child: Text(i.text)),
          ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Для вашей роли уведомлений нет', style: muted),
          ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: 'Уведомления',
        onPressed: () {
          if (menu.isOpen) {
            menu.close();
          } else {
            _refresh();
            menu.open();
          }
        },
        icon: Badge.count(
          count: total,
          isLabelVisible: total > 0,
          backgroundColor: AppColors.lowStock,
          child: const Icon(Icons.notifications_none_rounded),
        ),
      ),
    );
  }
}
