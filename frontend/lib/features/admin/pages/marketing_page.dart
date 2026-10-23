import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../data/admin_data.dart';
import '../data/admin_repository.dart';
import '../rbac.dart';
import '../widgets/admin_widgets.dart';
import '../widgets/photo_field.dart';

class MarketingPage extends ConsumerWidget {
  const MarketingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canMoney = ref
        .watch(permissionsProvider)
        .contains(Permission.pricingManage);
    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        const _Banners(),
        if (canMoney) ...[
          const SizedBox(height: Insets.xl),
          switch (ref.watch(referralSettingsProvider)) {
            AsyncData(:final value) => _ReferralCard(initial: value),
            AsyncError(:final error) => AdminCard(
              title: 'Приведи друга',
              child: Text('Не удалось загрузить: $error'),
            ),
            _ => const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
          },
        ],
      ],
    );
  }
}

class _Banners extends ConsumerWidget {
  const _Banners();

  Future<void> _edit(BuildContext context, AdminBanner? b) => showDialog<void>(
    context: context,
    builder: (_) => _BannerEditor(banner: b),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(bannersProvider);
    final n = ref.read(bannersProvider.notifier);
    return AdminCard(
      title: 'Баннеры на главной',
      subtitle: 'Листаются сами каждые 6 секунд. Порядок — как в списке',
      action: FilledButton.icon(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Новый баннер'),
      ),
      child: banners.isEmpty
          ? const EmptyState(
              icon: Icons.view_carousel_outlined,
              title: 'Баннеров пока нет',
              subtitle: 'Расскажите об акции, новинке или доставке — баннер будет первым, что увидит покупатель',
            )
          : Column(
              children: [
                for (final (i, b) in banners.indexed) ...[
                  if (i > 0) const SizedBox(height: Insets.md),
                  _BannerRow(
                    banner: b,
                    onEdit: () => _edit(context, b),
                    onUp: i == 0 ? null : () => n.move(b, -1),
                    onDown: i == banners.length - 1 ? null : () => n.move(b, 1),
                    onToggle: () => n.toggle(b),
                    onDelete: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text('Удалить баннер «${b.title}»?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Отмена'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.lowStock,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Удалить'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await n.delete(b);
                    },
                  ),
                ],
              ],
            ),
    );
  }
}

/// Мини-копия баннера с сайта — чтобы видеть результат до сохранения.
class BannerPreview extends StatelessWidget {
  const BannerPreview(this.b, {super.key, this.height = 120});
  final AdminBanner b;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: b.theme.background,
      borderRadius: BorderRadius.circular(Radii.lg),
    ),
    clipBehavior: Clip.antiAlias,
    padding: const EdgeInsets.symmetric(
      horizontal: Insets.lg,
      vertical: Insets.md,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  b.title.isEmpty ? 'Заголовок' : b.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: b.theme.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    height: 1.15,
                  ),
                ),
              ),
              if (b.text.isNotEmpty)
                Flexible(
                  child: Text(
                    b.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: b.theme.foreground.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                ),
              if (b.buttonLabel case final label? when label.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: b.buttonColor.background,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: b.buttonColor.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (b.imageUrl != null) ...[
          const SizedBox(width: Insets.md),
          SizedBox(
            width: height * 1.2,
            child: AppImage(imageUrl: b.imageUrl!, fit: BoxFit.contain),
          ),
        ],
      ],
    ),
  );
}

class _BannerRow extends StatelessWidget {
  const _BannerRow({
    required this.banner,
    required this.onEdit,
    required this.onUp,
    required this.onDown,
    required this.onToggle,
    required this.onDelete,
  });
  final AdminBanner banner;
  final VoidCallback onEdit;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final b = banner;
    final status = !b.isActive
        ? 'Скрыт'
        : b.visibleNow
        ? 'Показывается'
        : 'Запланирован';
    return LayoutBuilder(
      builder: (context, box) {
        final preview = Opacity(
          opacity: b.visibleNow ? 1 : 0.55,
          child: InkWell(onTap: onEdit, child: BannerPreview(b)),
        );
        final controls = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              status,
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: 12,
              ),
            ),
            IconButton(
              tooltip: 'Выше',
              onPressed: onUp,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            IconButton(
              tooltip: 'Ниже',
              onPressed: onDown,
              icon: const Icon(Icons.arrow_downward_rounded),
            ),
            IconButton(
              tooltip: b.isActive ? 'Скрыть' : 'Показать',
              onPressed: onToggle,
              icon: Icon(
                b.isActive
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Изменить',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Удалить',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        );
        return box.maxWidth < 640
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [preview, controls],
              )
            : Row(
                children: [
                  Expanded(child: preview),
                  const SizedBox(width: Insets.md),
                  controls,
                ],
              );
      },
    );
  }
}

class _BannerEditor extends ConsumerStatefulWidget {
  const _BannerEditor({this.banner});
  final AdminBanner? banner;

  @override
  ConsumerState<_BannerEditor> createState() => _BannerEditorState();
}

class _BannerEditorState extends ConsumerState<_BannerEditor> {
  late final b = widget.banner;
  late final _title = TextEditingController(text: b?.title);
  late final _text = TextEditingController(text: b?.text);
  late final _button = TextEditingController(text: b?.buttonLabel);
  late final _link = TextEditingController(text: b?.linkUrl);
  late String? _image = b?.imageUrl;
  late BannerTheme _theme = b?.theme ?? BannerTheme.green;
  late ButtonColor _buttonColor = b?.buttonColor ?? ButtonColor.orange;
  late bool _active = b?.isActive ?? true;
  late DateTime? _until = b?.endsAt;
  String? _error;
  bool _busy = false;

  static const _links = [
    ('/promo', 'Акции'),
    ('/catalog', 'Каталог'),
    ('/business', 'Для бизнеса'),
    ('/friends', 'Приведи друга'),
    ('/info/delivery', 'Доставка'),
  ];

  @override
  void dispose() {
    for (final c in [_title, _text, _button, _link]) {
      c.dispose();
    }
    super.dispose();
  }

  AdminBanner get _draft => AdminBanner(
    id: b?.id ?? 0,
    title: _title.text.trim(),
    text: _text.text.trim(),
    imageUrl: _image,
    buttonLabel: _button.text.trim().isEmpty ? null : _button.text.trim(),
    linkUrl: _link.text.trim().isEmpty ? null : _link.text.trim(),
    theme: _theme,
    buttonColor: _buttonColor,
    isActive: _active,
    startsAt: b?.startsAt,
    endsAt: _until,
  );

  Future<void> _save() async {
    final d = _draft;
    final link = d.linkUrl;
    final problem = d.title.isEmpty
        ? 'Напишите заголовок'
        : d.buttonLabel != null && link == null
        ? 'Для кнопки нужна ссылка'
        : link != null && !RegExp(r'^(/($|[^/\\])|https://)').hasMatch(link)
        ? 'Ссылка — страница сайта (/promo) или адрес https://…'
        : null;
    setState(() => _error = problem);
    if (problem != null) return;
    setState(() => _busy = true);
    final ok = await ref.read(bannersProvider.notifier).save(d);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.palette.textSecondary, fontSize: 12);
    return AlertDialog(
      title: Text(b == null ? 'Новый баннер' : 'Баннер'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BannerPreview(_draft, height: 130),
              const SizedBox(height: Insets.lg),
              TextField(
                controller: _title,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Заголовок',
                  hintText: 'Неделя ягод',
                ),
              ),
              TextField(
                controller: _text,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Текст',
                  hintText: 'Клубника и голубика со скидкой до 20%',
                ),
              ),
              const Text('Цвет', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: Insets.sm),
              SegmentedButton<BannerTheme>(
                showSelectedIcon: false,
                segments: [
                  for (final t in BannerTheme.values)
                    ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {_theme},
                onSelectionChanged: (v) => setState(() => _theme = v.first),
              ),
              const SizedBox(height: Insets.lg),
              PhotoField(
                value: _image,
                kind: 'banners',
                hint: 'Необязательно. Продукт на прозрачном фоне смотрится лучше всего',
                previewWidth: 120,
                previewHeight: 80,
                onChanged: (v) => setState(() => _image = v),
              ),
              const SizedBox(height: Insets.lg),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _button,
                      maxLength: 40,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Кнопка',
                        hintText: 'Смотреть',
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: TextField(
                      controller: _link,
                      decoration: const InputDecoration(
                        labelText: 'Ссылка',
                        hintText: '/promo',
                      ),
                    ),
                  ),
                ],
              ),
              const Text(
                'Цвет кнопки',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final c in ButtonColor.values)
                    ChoiceChip(
                      avatar: CircleAvatar(
                        radius: 8,
                        backgroundColor: c.background,
                        child: c == ButtonColor.white
                            ? const DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.fromBorderSide(
                                    BorderSide(color: Colors.black26),
                                  ),
                                ),
                                child: SizedBox.square(dimension: 16),
                              )
                            : null,
                      ),
                      label: Text(c.label),
                      selected: _buttonColor == c,
                      onSelected: (_) => setState(() => _buttonColor = c),
                    ),
                ],
              ),
              const SizedBox(height: Insets.md),
              const Text(
                'Куда ведёт кнопка',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: 6,
                children: [
                  for (final (url, label) in _links)
                    ActionChip(
                      label: Text(label),
                      onPressed: () => setState(() => _link.text = url),
                    ),
                ],
              ),
              const SizedBox(height: Insets.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Показывать на сайте'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _until == null
                          ? 'Без даты окончания'
                          : 'Показывать до ${_until!.day.toString().padLeft(2, '0')}.${_until!.month.toString().padLeft(2, '0')}.${_until!.year}',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                        initialDate: _until ?? now.add(const Duration(days: 7)),
                      );
                      if (d == null) return;
                      setState(
                        () => _until = DateTime(d.year, d.month, d.day, 23, 59),
                      );
                    },
                    child: const Text('Выбрать дату'),
                  ),
                  if (_until != null)
                    TextButton(
                      onPressed: () => setState(() => _until = null),
                      child: const Text('Убрать'),
                    ),
                ],
              ),
              Text('Акция закончилась — баннер скроется сам.', style: muted),
              if (_error case final e?) ...[
                const SizedBox(height: Insets.md),
                Text(
                  e,
                  style: const TextStyle(
                    color: AppColors.lowStock,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _ReferralCard extends ConsumerStatefulWidget {
  const _ReferralCard({required this.initial});
  final ReferralSettings initial;

  @override
  ConsumerState<_ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends ConsumerState<_ReferralCard> {
  late bool _on = widget.initial.enabled;
  late final _friend = TextEditingController(
    text: _fmt(widget.initial.friendAmount),
  );
  late final _inviter = TextEditingController(
    text: _fmt(widget.initial.inviterAmount),
  );
  late final _min = TextEditingController(text: _fmt(widget.initial.minOrder));
  bool _busy = false;

  static String _fmt(double v) => v.toStringAsFixed(0);
  static double? _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(' ', ''));

  @override
  void dispose() {
    _friend.dispose();
    _inviter.dispose();
    _min.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final f = _num(_friend), i = _num(_inviter), m = _num(_min);
    if (f == null || i == null || m == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .saveReferralSettings(
            ReferralSettings(
              enabled: _on,
              friendAmount: f,
              inviterAmount: i,
              minOrder: m,
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Условия программы сохранены')),
        );
      }
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label) => SizedBox(
    width: 220,
    child: TextField(
      controller: c,
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, suffixText: '₽'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final f = _num(_friend) ?? 0, i = _num(_inviter) ?? 0, m = _num(_min) ?? 0;
    final muted = TextStyle(color: context.palette.textSecondary);
    return AdminCard(
      title: 'Приведи друга',
      subtitle: 'Покупатель делится ссылкой — оба получают промокоды',
      action: Switch(value: _on, onChanged: (v) => setState(() => _on = v)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Insets.md,
            runSpacing: Insets.md,
            children: [
              _field(_friend, 'Другу на первый заказ'),
              _field(_inviter, 'Пригласившему'),
              _field(_min, 'Промокод действует от'),
            ],
          ),
          const SizedBox(height: Insets.md),
          Container(
            padding: const EdgeInsets.all(Insets.md),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Text(
              !_on
                  ? 'Программа выключена: ссылки не работают, страница «Приведи друга» и блок на главной скрыты.'
                  : [
                      if (f > 0)
                        'Друг регистрируется по ссылке и получает промокод на ${f.toStringAsFixed(0)} ₽ на первый заказ.',
                      if (i > 0)
                        'Когда друг получит свой первый заказ, пригласившему придёт промокод на ${i.toStringAsFixed(0)} ₽.',
                      'Промокоды одноразовые, действуют на заказ от ${m.toStringAsFixed(0)} ₽. Сумма 0 — этот бонус не выдаётся.',
                    ].join(' '),
              style: muted,
            ),
          ),
          const SizedBox(height: Insets.md),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}
