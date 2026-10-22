import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/delivery/delivery_check.dart';
import '../../../core/delivery/location_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../customer_session.dart';
import '../data/account_api.dart';

/// Добавление/редактирование адреса. Возвращает сохранённый адрес (или null при отмене).
Future<Address?> showAddressForm(BuildContext context, {Address? address}) =>
    showDialog<Address>(
      context: context,
      builder: (_) => _AddressForm(address: address),
    );

class _AddressForm extends ConsumerStatefulWidget {
  const _AddressForm({this.address});
  final Address? address;

  @override
  ConsumerState<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<_AddressForm> {
  final _form = GlobalKey<FormState>();
  late final a = widget.address;
  late String _label = a?.label ?? 'Дом';
  late final _address = TextEditingController(text: a?.address);
  late final _apartment = TextEditingController(text: a?.apartment);
  late final _entrance = TextEditingController(text: a?.entrance);
  late final _floor = TextEditingController(text: a?.floor);
  late final _intercom = TextEditingController(text: a?.intercom);
  late final _note = TextEditingController(text: a?.courierNote);
  late bool _default = a?.isDefault ?? false;
  bool _busy = false;
  String? _error;
  DeliveryVerdict? _zone;
  Timer? _debounce;
  late double? _lat = a?.lat, _lng = a?.lng; // точка с карты

  Future<void> _pickOnMap() async {
    final p = await showLocationPicker(context, lat: _lat, lng: _lng);
    if (p == null || !mounted) return;
    setState(() {
      _lat = p.lat;
      _lng = p.lng;
      if (p.address != null) _address.text = p.address!;
    });
    final v = await ref.read(deliveryCheckerProvider).checkPoint(p.lat, p.lng);
    if (mounted) setState(() => _zone = v);
  }

  @override
  void initState() {
    super.initState();
    if (_address.text.trim().length >= 5) _checkZone();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Подсказка, а не запрет: адрес можно сохранить (например, для самовывоза друга).
  void _checkZone() {
    _debounce?.cancel();
    final text = _address.text.trim();
    if (text.length < 5) return setState(() => _zone = null);
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      final v = await ref.read(deliveryCheckerProvider).check(text);
      if (mounted && text == _address.text.trim()) setState(() => _zone = v);
    });
  }

  static const _labels = ['Дом', 'Работа', 'Дача', 'Другое'];

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(addressesProvider.notifier)
          .save(
            Address(
              id: a?.id ?? 0,
              label: _label,
              address: _address.text.trim(),
              apartment: _opt(_apartment),
              entrance: _opt(_entrance),
              floor: _opt(_floor),
              intercom: _opt(_intercom),
              courierNote: _opt(_note),
              isDefault: _default,
              lat: _lat,
              lng: _lng,
            ),
          );
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget small(TextEditingController c, String label) => Expanded(
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return AlertDialog(
      title: Text(a == null ? 'Новый адрес' : 'Изменить адрес'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Insets.sm,
                  children: [
                    for (final l in _labels)
                      ChoiceChip(
                        label: Text(l),
                        selected: _label == l,
                        onSelected: (_) => setState(() => _label = l),
                      ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _address,
                  autofocus: a == null,
                  decoration: const InputDecoration(
                    labelText: 'Город, улица, дом',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  onChanged: (_) {
                    // руками поменяли адрес — точка с карты больше не соответствует
                    setState(() => _lat = _lng = null);
                    _checkZone();
                  },
                  validator: (v) => _lat != null
                      ? ((v ?? '').trim().length < 3 ? 'Укажите адрес' : null)
                      : addressProblem(v ?? ''),
                ),
                const SizedBox(height: Insets.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _pickOnMap,
                    icon: Icon(
                      _lat == null ? Icons.map_outlined : Icons.where_to_vote,
                      size: 18,
                    ),
                    label: Text(
                      _lat == null
                          ? 'Выбрать на карте'
                          : 'Точка на карте выбрана — изменить',
                    ),
                  ),
                ),
                if (_zone case final z? when !z.ok)
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.wrong_location_outlined,
                          size: 18,
                          color: AppColors.hit,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            z.reason ?? 'Сюда мы пока не доставляем',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    small(_apartment, 'Квартира'),
                    const SizedBox(width: Insets.sm),
                    small(_entrance, 'Подъезд'),
                  ],
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    small(_floor, 'Этаж'),
                    const SizedBox(width: Insets.sm),
                    small(_intercom, 'Домофон'),
                  ],
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Комментарий курьеру',
                    hintText: 'Например: шлагбаум с торца',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Основной адрес'),
                  subtitle: const Text('Подставляется при оформлении заказа'),
                  value: _default,
                  onChanged: (v) => setState(() => _default = v),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.lowStock),
                  ),
              ],
            ),
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
