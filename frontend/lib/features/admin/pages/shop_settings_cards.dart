import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/admin_data.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';

double? _num(TextEditingController c) =>
    double.tryParse(c.text.replaceAll(' ', '').replaceAll(',', '.'));

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class _MoneyField extends StatelessWidget {
  const _MoneyField(this.controller, this.label);
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      decoration: InputDecoration(labelText: label, suffixText: '₽'),
    ),
  );
}

/// Контакты, условия доставки и реквизиты — одна запись на сервере, поэтому одна кнопка «Сохранить».
class ShopSettingsCards extends ConsumerStatefulWidget {
  const ShopSettingsCards({super.key, required this.initial});
  final ShopSettings initial;

  @override
  ConsumerState<ShopSettingsCards> createState() => _ShopSettingsCardsState();
}

class _ShopSettingsCardsState extends ConsumerState<ShopSettingsCards> {
  late ShopSettings s = widget.initial;
  late final _phone = TextEditingController(text: s.phone);
  late final _email = TextEditingController(text: s.email);
  late final _min = TextEditingController(text: _fmt(s.minOrder));
  late final _courier = TextEditingController(text: _fmt(s.courierFee));
  late final _freeFrom = TextEditingController(
    text: s.freeFrom == null || s.freeFrom == 0 ? '' : _fmt(s.freeFrom!),
  );
  late final _express = TextEditingController(text: _fmt(s.expressFee));
  late final _legalName = TextEditingController(text: s.legalName);
  late final _inn = TextEditingController(text: s.legalInn);
  late final _ogrn = TextEditingController(text: s.legalOgrn);
  late final _address = TextEditingController(text: s.legalAddress);
  // как считать курьера: paid — всегда платно, threshold — бесплатно от суммы, free — всегда бесплатно
  late String _courierMode = s.freeFrom == null
      ? 'paid'
      : s.freeFrom == 0
      ? 'free'
      : 'threshold';
  late bool _expressOn = s.expressEnabled;
  late int _expressHours = s.expressHours;
  late bool _pickupOn = s.pickupEnabled;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _phone,
      _email,
      _min,
      _courier,
      _freeFrom,
      _express,
      _legalName,
      _inn,
      _ogrn,
      _address,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate() {
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      return 'Укажите телефон магазина';
    }
    final email = _email.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Проверьте почту';
    }
    for (final (c, name) in [
      (_min, 'Минимальный заказ'),
      (_courier, 'Стоимость курьера'),
      (_express, 'Стоимость экспресса'),
    ]) {
      if (_num(c) == null || _num(c)! < 0) return '$name — укажите сумму';
    }
    if (_courierMode == 'threshold' && (_num(_freeFrom) ?? 0) <= 0) {
      return 'Укажите, с какой суммы курьер бесплатный';
    }
    final inn = _inn.text.trim();
    if (inn.isNotEmpty && !RegExp(r'^(\d{10}|\d{12})$').hasMatch(inn)) {
      return 'ИНН — 10 цифр у компании или 12 у ИП';
    }
    final ogrn = _ogrn.text.trim();
    if (ogrn.isNotEmpty && !RegExp(r'^(\d{13}|\d{15})$').hasMatch(ogrn)) {
      return 'ОГРН — 13 цифр, ОГРНИП — 15';
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    setState(() => _error = problem);
    if (problem != null) return;
    setState(() => _busy = true);
    final next = ShopSettings(
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      minOrder: _num(_min)!,
      courierFee: _num(_courier)!,
      freeFrom: switch (_courierMode) {
        'paid' => null,
        'free' => 0,
        _ => _num(_freeFrom),
      },
      expressEnabled: _expressOn,
      expressFee: _num(_express)!,
      expressHours: _expressHours,
      pickupEnabled: _pickupOn,
      legalName: _legalName.text.trim(),
      legalInn: _inn.text.trim(),
      legalOgrn: _ogrn.text.trim(),
      legalAddress: _address.text.trim(),
    );
    try {
      s = await ref.read(adminRepositoryProvider).saveShopSettings(next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сохранено — на сайте уже новые условия'),
          ),
        );
      }
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _switchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    value: value,
    onChanged: (v) => setState(() => onChanged(v)),
  );

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.palette.textSecondary, fontSize: 13);
    final save = Align(
      alignment: Alignment.centerRight,
      child: FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('Сохранить'),
      ),
    );
    final error = _error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            child: Text(
              _error!,
              style: const TextStyle(
                color: AppColors.lowStock,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminCard(
          title: 'Условия доставки',
          subtitle: 'Сразу меняются на сайте: в корзине, при оформлении и на странице «Доставка»',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MoneyField(_min, 'Минимальный заказ на доставку'),
              const SizedBox(height: 4),
              Text(
                'Курьер и экспресс — только от этой суммы. Самовывоз — на любую сумму.',
                style: muted,
              ),
              const SizedBox(height: Insets.lg),
              const Text(
                'Курьер',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Insets.sm),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: 'threshold',
                    label: Text('Бесплатно от суммы'),
                  ),
                  ButtonSegment(value: 'paid', label: Text('Всегда платно')),
                  ButtonSegment(value: 'free', label: Text('Всегда бесплатно')),
                ],
                selected: {_courierMode},
                onSelectionChanged: (v) =>
                    setState(() => _courierMode = v.first),
              ),
              const SizedBox(height: Insets.md),
              Wrap(
                spacing: Insets.md,
                runSpacing: Insets.md,
                children: [
                  if (_courierMode != 'free')
                    _MoneyField(_courier, 'Стоимость курьера'),
                  if (_courierMode == 'threshold')
                    _MoneyField(_freeFrom, 'Бесплатно от'),
                ],
              ),
              const Divider(height: Insets.xxl),
              _switchRow(
                'Экспресс-доставка',
                _expressOn
                    ? 'Покупатели могут выбрать срочную доставку'
                    : 'Выключена — на сайте её не видно',
                _expressOn,
                (v) => _expressOn = v,
              ),
              if (_expressOn)
                Wrap(
                  spacing: Insets.md,
                  runSpacing: Insets.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MoneyField(_express, 'Стоимость экспресса'),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<int>(
                        initialValue: _expressHours,
                        decoration: const InputDecoration(
                          labelText: 'Привезём за',
                        ),
                        items: [
                          for (final h in const [1, 2, 3, 4, 5, 6, 8])
                            DropdownMenuItem(value: h, child: Text('$h ч')),
                        ],
                        onChanged: (v) =>
                            setState(() => _expressHours = v ?? 2),
                      ),
                    ),
                  ],
                ),
              const Divider(height: Insets.xxl),
              _switchRow(
                'Самовывоз',
                _pickupOn
                    ? 'Бесплатно, в часы работы магазина'
                    : 'Выключен — на сайте его не видно',
                _pickupOn,
                (v) => _pickupOn = v,
              ),
              const SizedBox(height: Insets.md),
              error,
              save,
            ],
          ),
        ),
        const SizedBox(height: Insets.xl),
        AdminCard(
          title: 'Контакты и реквизиты',
          subtitle: 'Телефон и почта — в шапке, подвале и на «Контактах»; реквизиты — в оферте и подвале',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Insets.md,
                runSpacing: Insets.md,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Телефон для покупателей',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Почта для покупателей',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),
              TextField(
                controller: _legalName,
                decoration: const InputDecoration(
                  labelText: 'Продавец',
                  hintText: 'ООО «Фудтор» или ИП Иванов Иван Иванович',
                ),
              ),
              const SizedBox(height: Insets.md),
              Wrap(
                spacing: Insets.md,
                runSpacing: Insets.md,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _inn,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'ИНН'),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _ogrn,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'ОГРН / ОГРНИП',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _address,
                decoration: const InputDecoration(
                  labelText: 'Юридический адрес',
                ),
              ),
              const SizedBox(height: Insets.sm),
              Text(
                'Реквизиты обязательны для оферты: без них покупатель не видит, с кем заключает договор.',
                style: muted,
              ),
              const SizedBox(height: Insets.md),
              error,
              save,
            ],
          ),
        ),
      ],
    );
  }
}
