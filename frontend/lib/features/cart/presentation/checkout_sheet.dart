import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/delivery/delivery_check.dart';
import '../../../core/delivery/location_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/customer_session.dart';
import '../../account/data/account_api.dart';
import '../../catalog/presentation/providers/shop_providers.dart';
import '../../catalog/presentation/widgets/price_tag.dart';
import '../data/checkout_api.dart';
import 'cart_checkout.dart';

/// Оформление заказа (релиз): контакты → способ оплаты → серверный итог → «Оформить».
/// Онлайн-оплата: после создания заказа уходим на страницу Альфа-Банка в той же вкладке.
Future<void> showCheckoutSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const _CheckoutSheet(),
    );

class _CheckoutSheet extends ConsumerStatefulWidget {
  const _CheckoutSheet();

  @override
  ConsumerState<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<_CheckoutSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: ref.read(customerSessionProvider).value?.fullName ?? '',
  );
  late final _phone = TextEditingController(
    text: ref.read(customerSessionProvider).value?.phone ?? '',
  );
  final _address = TextEditingController();
  int? _addressId; // выбранный сохранённый адрес; null — ввести новый
  bool _addressTouched = false;
  bool _saveAddress = true;
  final _note = TextEditingController();
  PaymentChoice _payment = PaymentChoice.cardOnline;
  Future<ServerQuote>? _quote;
  bool _busy = false;
  String? _error;

  // Зона доставки: проверяем адрес заранее, чтобы не дать оформить заказ, который не довезём
  DeliveryVerdict? _zone;
  String _zoneFor = '';
  bool _zoneLoading = false;
  Timer? _debounce;
  double? _pickedLat, _pickedLng; // точка с карты для нового адреса

  /// Координаты текущего адреса: выбранного сохранённого (если у него есть точка) или с карты.
  (double, double)? get _targetPoint {
    final saved = ref.read(addressesProvider).value ?? const <Address>[];
    final picked = saved.where((a) => a.id == _addressId).firstOrNull;
    if (picked != null) {
      return picked.lat != null ? (picked.lat!, picked.lng!) : null;
    }
    return _pickedLat != null ? (_pickedLat!, _pickedLng!) : null;
  }

  Future<DeliveryVerdict> _checkTarget(String address) {
    final checker = ref.read(deliveryCheckerProvider);
    final p = _targetPoint;
    return p != null ? checker.checkPoint(p.$1, p.$2) : checker.check(address);
  }

  Future<void> _pickOnMap() async {
    final p = await showLocationPicker(
      context,
      lat: _pickedLat,
      lng: _pickedLng,
    );
    if (p == null || !mounted) return;
    setState(() {
      _pickedLat = p.lat;
      _pickedLng = p.lng;
      if (p.address != null) _address.text = p.address!;
      _zoneFor = '';
    });
    _checkZone(now: true);
  }

  Map<int, int> get _lines => {
    for (final e in ref.read(cartProvider).values) e.product.id: e.quantity,
  };

  @override
  void initState() {
    super.initState();
    _refreshQuote();
    // основной адрес подставляется сам — проверяем его, как только адреса загрузились
    ref.listenManual(
      addressesProvider,
      (_, _) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkZone(now: true);
      }),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _phone, _address, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refreshQuote() => setState(() {
    _quote = ref
        .read(checkoutApiProvider)
        .quote(
          _lines,
          ref.read(deliveryChoiceProvider),
          ref.read(promoProvider)?.code,
        );
  });

  bool get _pickup => ref.read(deliveryChoiceProvider) == DeliveryChoice.pickup;

  /// Адрес, по которому сейчас поедет курьер (сохранённый или введённый вручную).
  String get _targetAddress {
    final saved = ref.read(addressesProvider).value ?? const <Address>[];
    return saved.where((a) => a.id == _addressId).firstOrNull?.address ??
        _address.text.trim();
  }

  bool get _outOfZone =>
      !_pickup && _zone != null && !_zone!.ok && _zoneFor == _targetAddress;

  /// Проверка адреса: сразу для выбранного из книги, с паузой — пока человек печатает.
  void _checkZone({bool now = false}) {
    _debounce?.cancel();
    final address = _targetAddress;
    if (_pickup || address.length < 5) {
      setState(() => _zone = null);
      return;
    }
    if (address == _zoneFor && _zone != null) return;
    _debounce = Timer(
      now ? Duration.zero : const Duration(milliseconds: 700),
      () async {
        setState(() => _zoneLoading = true);
        final v = await _checkTarget(address);
        if (!mounted || address != _targetAddress) return;
        setState(() {
          _zone = v;
          _zoneFor = address;
          _zoneLoading = false;
        });
      },
    );
  }

  void _switchToPickup() {
    ref.read(deliveryChoiceProvider.notifier).set(DeliveryChoice.pickup);
    setState(() => _zone = null);
    _refreshQuote();
  }

  /// Строка адреса для заказа: выбранный из адресной книги или новый (по желанию — сохраняется).
  Future<String> _resolveAddress() async {
    if (ref.read(deliveryChoiceProvider) == DeliveryChoice.pickup) {
      return 'Самовывоз';
    }
    final saved = ref.read(addressesProvider).value ?? const [];
    final picked = saved.where((a) => a.id == _addressId).firstOrNull;
    if (picked != null) {
      return [
        picked.oneLine,
        if (picked.courierNote != null) 'курьеру: ${picked.courierNote}',
      ].join('; ');
    }
    final text = _address.text.trim();
    if (_saveAddress) {
      try {
        await ref
            .read(addressesProvider.notifier)
            .save(
              Address(
                id: 0,
                address: text,
                label: saved.isEmpty ? 'Дом' : 'Другое',
                lat: _pickedLat,
                lng: _pickedLng,
              ),
            );
      } catch (_) {} // адрес не сохранился — заказ всё равно оформляем
    }
    return text;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_pickup) {
        final address = _targetAddress;
        final v = await _checkTarget(address);
        if (!mounted) return;
        setState(() {
          _zone = v;
          _zoneFor = address;
        });
        if (!v.ok) return; // предупреждение уже на экране
      }
      final order = await ref
          .read(checkoutApiProvider)
          .place(
            lines: _lines,
            delivery: ref.read(deliveryChoiceProvider),
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            address: await _resolveAddress(),
            payment: _payment,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            promo: ref.read(promoProvider)?.code,
            lat: _pickup ? null : _targetPoint?.$1,
            lng: _pickup ? null : _targetPoint?.$2,
          );
      clearCart(ref);
      ref.invalidate(myOrdersProvider);
      if (!mounted) return;
      if (order.payUrl case final url?) {
        // Та же вкладка: после оплаты банк вернёт покупателя на сайт (/#/payment?result=…)
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
        return;
      }
      Navigator.of(context).pop();
      await showOrderPlacedDialog(
        context,
        order.number,
        order.total,
        // в демо банка нет — считаем, что оплата картой прошла
        paid: AppConfig.isDemo && _payment == PaymentChoice.cardOnline,
      );
    } catch (e) {
      setState(() => _error = e.toString());
      _refreshQuote(); // цены/остатки могли измениться
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _savedAddressPicker(BuildContext context) {
    final saved = ref.watch(addressesProvider).value ?? const <Address>[];
    if (!_addressTouched && _addressId == null && saved.isNotEmpty) {
      _addressId = (saved.where((a) => a.isDefault).firstOrNull ?? saved.first)
          .id; // основной — по умолчанию
    }
    return [
      if (saved.isNotEmpty)
        RadioGroup<int?>(
          groupValue: _addressId,
          onChanged: (v) {
            setState(() {
              _addressId = v;
              _addressTouched = true;
            });
            _checkZone(now: true);
          },
          child: Column(
            children: [
              for (final a in saved)
                RadioListTile<int?>(
                  value: a.id,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    a.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    a.oneLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const RadioListTile<int?>(
                value: null,
                contentPadding: EdgeInsets.zero,
                title: Text('Другой адрес'),
              ),
            ],
          ),
        ),
      if (_addressId == null)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _saveAddress,
          onChanged: (v) => setState(() => _saveAddress = v ?? false),
          title: const Text('Сохранить в «Мои адреса»'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pickup = ref.watch(deliveryChoiceProvider) == DeliveryChoice.pickup;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.xl),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Оформление заказа', style: text.headlineSmall),
              const SizedBox(height: Insets.lg),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Получатель',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => (v ?? '').trim().length < 2
                    ? 'Укажите имя получателя'
                    : null,
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Телефон',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) =>
                    RegExp(r'^\+?[0-9 ()\-]{7,20}$').hasMatch((v ?? '').trim())
                    ? null
                    : 'Проверьте телефон',
              ),
              if (!pickup) ...[
                const SizedBox(height: Insets.lg),
                Text(
                  'Адрес доставки',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Insets.sm),
                ..._savedAddressPicker(context),
              ],
              if (!pickup && _addressId == null) ...[
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _address,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Адрес доставки',
                    hintText: 'Улица, дом, квартира, подъезд, этаж',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  onChanged: (_) => _checkZone(),
                  // с точкой на карте строка — лишь подпись для курьера (квартира, подъезд)
                  validator: (v) => _pickedLat != null
                      ? ((v ?? '').trim().length < 3 ? 'Укажите адрес' : null)
                      : addressProblem(v ?? ''),
                ),
                const SizedBox(height: Insets.xs),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _pickOnMap,
                    icon: Icon(
                      _pickedLat == null
                          ? Icons.map_outlined
                          : Icons.where_to_vote,
                      size: 18,
                    ),
                    label: Text(
                      _pickedLat == null
                          ? 'Выбрать на карте · моё местоположение'
                          : 'Точка на карте выбрана — изменить',
                    ),
                  ),
                ),
              ],
              if (!pickup)
                _ZoneStatus(
                  verdict: _zoneFor == _targetAddress ? _zone : null,
                  loading: _zoneLoading,
                  onPickup: _switchToPickup,
                  onMap: _addressId == null ? _pickOnMap : null,
                ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (необязательно)',
                  prefixIcon: Icon(Icons.chat_bubble_outline),
                ),
              ),
              const SizedBox(height: Insets.xl),
              Text(
                'Оплата',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Insets.sm),
              RadioGroup<PaymentChoice>(
                groupValue: _payment,
                onChanged: (v) => setState(() => _payment = v!),
                child: const Column(
                  children: [
                    RadioListTile(
                      value: PaymentChoice.cardOnline,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Картой онлайн'),
                      subtitle: Text(
                        'Visa, Mastercard, МИР, СБП — через Альфа-Банк',
                      ),
                    ),
                    RadioListTile(
                      value: PaymentChoice.cash,
                      contentPadding: EdgeInsets.zero,
                      title: Text('При получении'),
                      subtitle: Text('Наличными или картой курьеру'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),
              FutureBuilder<ServerQuote>(
                future: _quote,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(
                      snap.error.toString(),
                      style: const TextStyle(color: AppColors.lowStock),
                    );
                  }
                  final q = snap.data;
                  if (q == null) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(Insets.lg),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  Widget row(
                    String l,
                    String v, {
                    Color? color,
                    bool bold = false,
                  }) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l,
                            style: TextStyle(
                              color: bold
                                  ? null
                                  : context.palette.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          v,
                          style: TextStyle(
                            color: color,
                            fontWeight: bold
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: bold ? 18 : null,
                          ),
                        ),
                      ],
                    ),
                  );
                  return Container(
                    padding: const EdgeInsets.all(Insets.lg),
                    decoration: BoxDecoration(
                      color: context.palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Column(
                      children: [
                        row('Товары', rub.format(q.subtotal)),
                        if (q.loyaltyDiscount > 0)
                          row(
                            'Скидка${q.tierName != null ? ' ${q.tierName}' : ''}',
                            '−${rub.format(q.loyaltyDiscount)}',
                            color: AppColors.lowStock,
                          ),
                        if (q.promoDiscount > 0)
                          row(
                            'Промокод',
                            '−${rub.format(q.promoDiscount)}',
                            color: AppColors.lowStock,
                          ),
                        if (q.promoError != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              q.promoError!,
                              style: const TextStyle(
                                color: AppColors.hit,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        row(
                          'Доставка',
                          q.deliveryFee == 0
                              ? 'Бесплатно'
                              : rub.format(q.deliveryFee),
                          color: q.deliveryFee == 0 ? AppColors.fresh : null,
                        ),
                        const Divider(height: Insets.lg),
                        row('К оплате', rub.format(q.total), bold: true),
                      ],
                    ),
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: Insets.md),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.lowStock),
                ),
              ],
              const SizedBox(height: Insets.lg),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: _busy || _outOfZone ? null : _submit,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(
                        _payment == PaymentChoice.cardOnline
                            ? Icons.lock_outline_rounded
                            : Icons.check_rounded,
                      ),
                label: Text(
                  _payment == PaymentChoice.cardOnline
                      ? 'Перейти к оплате'
                      : 'Оформить заказ',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoneStatus extends StatelessWidget {
  const _ZoneStatus({
    required this.verdict,
    required this.loading,
    required this.onPickup,
    this.onMap,
  });
  final DeliveryVerdict? verdict;
  final bool loading;
  final VoidCallback onPickup;
  final VoidCallback? onMap;

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    if (v == null) {
      return loading
          ? const Padding(
              padding: EdgeInsets.only(top: Insets.sm),
              child: LinearProgressIndicator(minHeight: 2),
            )
          : const SizedBox.shrink();
    }
    if (v.ok) {
      if (v.distanceKm == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Insets.sm),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: AppColors.fresh,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Доставляем по этому адресу',
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (v.needsDetails) {
      return Container(
        key: const ValueKey('zone-details'),
        margin: const EdgeInsets.only(top: Insets.md),
        padding: const EdgeInsets.all(Insets.md),
        decoration: BoxDecoration(
          color: AppColors.hit.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.hit.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.edit_location_alt_outlined,
                  color: AppColors.hit,
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    v.reason ?? needHouseMessage,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (onMap != null) ...[
              const SizedBox(height: Insets.sm),
              OutlinedButton.icon(
                onPressed: onMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('Выбрать на карте'),
              ),
            ],
          ],
        ),
      );
    }
    return Container(
      key: const ValueKey('zone-warning'),
      margin: const EdgeInsets.only(top: Insets.md),
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: AppColors.lowStock.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.lowStock.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.wrong_location_outlined, color: AppColors.lowStock),
              SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  'Мы не доставляем по вашему адресу',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.lowStock,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(v.reason ?? 'Адрес вне зоны доставки.'),
          const SizedBox(height: Insets.sm),
          OutlinedButton.icon(
            onPressed: onPickup,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Заберу сам — самовывоз'),
          ),
        ],
      ),
    );
  }
}

void clearCart(WidgetRef ref) {
  ref.read(promoProvider.notifier).clear();
  final cart = ref.read(cartProvider.notifier);
  for (final id in ref.read(cartProvider).keys.toList()) {
    cart.delete(id);
  }
  ref.read(promoProvider.notifier).clear();
}

Future<void> showOrderPlacedDialog(
  BuildContext context,
  String number,
  double total, {
  required bool paid,
}) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    icon: const Icon(
      Icons.check_circle_rounded,
      color: AppColors.fresh,
      size: 56,
    ),
    title: Text('Заказ $number оформлен'),
    content: Text(
      paid
          ? 'Оплата прошла. Мы уже собираем ваш заказ.'
          : 'Сумма: ${rub.format(total)}. Оплата при получении.',
      textAlign: TextAlign.center,
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(c),
        child: const Text('Отлично'),
      ),
    ],
  ),
);
