import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../data/admin_data.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

class BusinessPage extends ConsumerWidget {
  const BusinessPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(Insets.xl),
    children: [
      switch (ref.watch(wholesaleMinOrderProvider)) {
        AsyncData(:final value) => _TermsCard(initial: value),
        AsyncError(:final error) => AdminCard(
          title: 'Условия для оптовиков',
          child: Text('Не удалось загрузить: $error'),
        ),
        _ => const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      },
      const SizedBox(height: Insets.xl),
      const _Companies(),
    ],
  );
}

class _TermsCard extends ConsumerStatefulWidget {
  const _TermsCard({required this.initial});
  final double initial;

  @override
  ConsumerState<_TermsCard> createState() => _TermsCardState();
}

class _TermsCardState extends ConsumerState<_TermsCard> {
  late double _saved = widget.initial;
  late final _min = TextEditingController(
    text: widget.initial.toStringAsFixed(0),
  );
  bool _busy = false;

  double? get _value => double.tryParse(_min.text.replaceAll(' ', ''));

  @override
  void dispose() {
    _min.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _value;
    if (v == null || v < 0) return;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(adminRepositoryProvider)
          .saveWholesaleMinOrder(v);
      if (!mounted) return;
      setState(() => _saved = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == 0
                ? 'Минимальный заказ для оптовиков отключён'
                : 'Минимальный заказ для оптовиков — ${money.format(saved)}',
          ),
        ),
      );
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.palette.textSecondary);
    final v = _value;
    return AdminCard(
      title: 'Условия для оптовиков',
      subtitle: 'Оптовая цена задаётся в карточке товара (раздел «Товары»). Её видят только подтверждённые компании',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Insets.lg,
            runSpacing: Insets.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Минимальный заказ',
                    suffixText: '₽',
                  ),
                ),
              ),
              FilledButton(
                onPressed: !_busy && v != null && v != _saved ? _save : null,
                child: const Text('Сохранить'),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Text(
            v == null || v == 0
                ? 'Без ограничения: оптовик может оформить заказ на любую сумму'
                : 'Если товаров по оптовым ценам меньше чем на ${money.format(v)}, '
                      'оформить заказ нельзя — корзина подскажет, сколько добавить',
            style: muted,
          ),
        ],
      ),
    );
  }
}

class _Companies extends ConsumerStatefulWidget {
  const _Companies();

  @override
  ConsumerState<_Companies> createState() => _CompaniesState();
}

class _CompaniesState extends ConsumerState<_Companies> {
  B2BStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(companiesProvider);
    final shown = [
      for (final c in all)
        if (_filter == null || c.status == _filter) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Заявки компаний',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Insets.md),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            ChoiceChip(
              label: Text('Все · ${all.length}'),
              selected: _filter == null,
              onSelected: (_) => setState(() => _filter = null),
            ),
            for (final s in [
              B2BStatus.pending,
              B2BStatus.approved,
              B2BStatus.rejected,
            ])
              ChoiceChip(
                label: Text(
                  '${s.label} · ${all.where((c) => c.status == s).length}',
                ),
                selected: _filter == s,
                onSelected: (_) => setState(() => _filter = s),
              ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        if (shown.isEmpty)
          const EmptyState(
            icon: Icons.storefront_outlined,
            title: 'Заявок нет',
            subtitle:
                'Компании оставляют заявку на сайте в разделе «Для бизнеса»',
          )
        else
          for (final c in shown) ...[
            _CompanyCard(company: c),
            const SizedBox(height: Insets.md),
          ],
      ],
    );
  }
}

class _CompanyCard extends ConsumerWidget {
  const _CompanyCard({required this.company});
  final B2BCompany company;

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    final note = TextEditingController();
    final c = company;
    final (title, hint, action) = switch ((approve, c.status)) {
      (true, _) => (
        'Подтвердить «${c.legalName}»?',
        'Сотрудники компании сразу увидят оптовые цены на сайте.',
        'Подтвердить',
      ),
      (false, B2BStatus.approved) => (
        'Отключить оптовые цены для «${c.legalName}»?',
        'Компания снова будет видеть розничные цены.',
        'Отключить',
      ),
      _ => (
        'Отклонить заявку «${c.legalName}»?',
        'Компания сможет исправить данные и отправить заявку ещё раз.',
        'Отклонить',
      ),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(hint),
              const SizedBox(height: Insets.md),
              TextField(
                controller: note,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (видят только сотрудники)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: approve
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: AppColors.lowStock,
                    foregroundColor: Colors.white,
                  ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true) return;
    await ref
        .read(companiesProvider.notifier)
        .decide(c, approve: approve, note: text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = company;
    final muted = TextStyle(color: context.palette.textSecondary);
    return AdminCard(
      title: c.legalName,
      subtitle:
          'ИНН ${c.taxId} · заявка от ${DateFormat('d MMMM y', 'ru').format(c.createdAt)}',
      action: _Badge(c.status.label, c.status.color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in c.members)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: Insets.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 18,
                        color: context.palette.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(m.name),
                    ],
                  ),
                  if (m.phone case final phone?)
                    SelectableText(_prettyPhone(phone), style: muted),
                  if (m.email case final email?)
                    SelectableText(email, style: muted),
                ],
              ),
            ),
          if (c.note case final note? when note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Text('Комментарий: $note', style: muted),
            ),
          const SizedBox(height: Insets.lg),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              if (c.status != B2BStatus.approved)
                FilledButton.icon(
                  onPressed: () => _decide(context, ref, approve: true),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Подтвердить'),
                ),
              if (c.status == B2BStatus.pending ||
                  c.status == B2BStatus.approved)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.lowStock,
                  ),
                  onPressed: () => _decide(context, ref, approve: false),
                  child: Text(
                    c.status == B2BStatus.pending ? 'Отклонить' : 'Отключить',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _prettyPhone(String p) {
  final d = p.replaceAll(RegExp(r'\D'), '');
  if (d.length != 11) return p;
  return '+7 (${d.substring(1, 4)}) ${d.substring(4, 7)}-${d.substring(7, 9)}-${d.substring(9)}';
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}
