import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/delivery/delivery_check.dart';
import '../../../core/delivery/location_picker.dart' show OsmAttribution;
import '../../../core/theme/app_theme.dart';
import '../data/admin_data.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_widgets.dart';
import 'shop_settings_cards.dart';

class DeliverySettingsPage extends ConsumerWidget {
  const DeliverySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = ref.watch(deliveryZoneProvider);
    final hours = ref.watch(workHoursProvider);
    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        switch (zone) {
          AsyncData(:final value) => _ZoneEditor(initial: value),
          AsyncError(:final error) => AdminCard(
            title: 'Зона доставки',
            child: Text('Не удалось загрузить настройки: $error'),
          ),
          _ => const SizedBox(
            height: 320,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
        const SizedBox(height: Insets.xl),
        switch (ref.watch(shopSettingsProvider)) {
          AsyncData(:final value) => ShopSettingsCards(initial: value),
          AsyncError(:final error) => AdminCard(
            title: 'Условия доставки',
            child: Text('Не удалось загрузить настройки: $error'),
          ),
          _ => const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
        const SizedBox(height: Insets.xl),
        switch (hours) {
          AsyncData(:final value) => _HoursCard(initial: value),
          AsyncError(:final error) => AdminCard(
            title: 'Часы работы',
            child: Text('Не удалось загрузить часы работы: $error'),
          ),
          _ => const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
        const SizedBox(height: Insets.xl),
        switch (ref.watch(socialsProvider)) {
          AsyncData(:final value) => _SocialsCard(initial: value),
          AsyncError(:final error) => AdminCard(
            title: 'Соцсети',
            child: Text('Не удалось загрузить соцсети: $error'),
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _ZoneEditor extends ConsumerStatefulWidget {
  const _ZoneEditor({required this.initial});
  final DeliveryZone initial;

  @override
  ConsumerState<_ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends ConsumerState<_ZoneEditor> {
  late DeliveryZone _saved = widget.initial;
  late DeliveryZone _draft = widget.initial;
  late final _address = TextEditingController(text: _draft.storeAddress);
  final _map = MapController();
  final _probe = TextEditingController();
  final _city = TextEditingController();

  static const _citySuggestions = [
    'Москва', 'Зеленоград', 'Химки', 'Мытищи', 'Королёв', 'Балашиха', //
    'Люберцы', 'Красногорск', 'Одинцово', 'Подольск', 'Домодедово',
  ];

  void _addCity(String raw) {
    final c = raw.trim();
    if (c.length < 2) return;
    if (_draft.cities.any((x) => x.toLowerCase() == c.toLowerCase())) return;
    setState(() {
      _draft = _draft.copyWith(cities: [..._draft.cities, c]);
      _city.clear();
    });
  }

  void _removeCity(String c) => setState(
    () => _draft = _draft.copyWith(
      cities: [
        for (final x in _draft.cities)
          if (x != c) x,
      ],
    ),
  );
  bool _pinned =
      true; // точка поставлена на карте (иначе сервер найдёт адрес сам)
  bool _busy = false;
  bool _mapReady = false;
  DeliveryVerdict? _probeResult;

  static const _presets = [5.0, 10.0, 20.0, 30.0, 50.0];

  bool get _dirty =>
      _draft.enabled != _saved.enabled ||
      _draft.radiusKm != _saved.radiusKm ||
      _draft.lat != _saved.lat ||
      _draft.lng != _saved.lng ||
      _address.text.trim() != _saved.storeAddress ||
      _draft.cities.join('|') != _saved.cities.join('|');

  @override
  void dispose() {
    _address.dispose();
    _probe.dispose();
    _city.dispose();
    _map.dispose();
    super.dispose();
  }

  /// Масштаб, при котором круг целиком помещается в окно карты.
  void _fit(double side) {
    if (!_mapReady) return;
    final metersPerPx = _draft.radiusKm * 1000 * 2.5 / max(side, 200);
    final zoom =
        log(156543.03 * cos(_draft.lat * pi / 180) / metersPerPx) / ln2;
    _map.move(LatLng(_draft.lat, _draft.lng), zoom.clamp(3, 16));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final addressChanged = _address.text.trim() != _saved.storeAddress;
      final result = await ref
          .read(adminRepositoryProvider)
          .saveDeliveryZone(
            _draft.copyWith(storeAddress: _address.text.trim()),
            pinned: _pinned || !addressChanged,
          );
      setState(() {
        _saved = _draft = result;
        _pinned = true;
        _probeResult = null;
      });
      _fit(_lastSide);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.enabled
                ? 'Сохранено: возим в радиусе ${_km(result.radiusKm)}'
                      '${result.cities.isEmpty ? '' : ' и по городам: ${result.cities.join(', ')}'}'
                : 'Сохранено: ограничение по зоне выключено',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    if (_probe.text.trim().length < 3) return;
    final v = await ref.read(deliveryCheckerProvider).check(_probe.text);
    if (mounted) setState(() => _probeResult = v);
  }

  double _lastSide = 400;

  static String _km(double v) =>
      '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} км';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final center = LatLng(_draft.lat, _draft.lng);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final map = LayoutBuilder(
      builder: (context, c) {
        _lastSide = min(c.maxWidth, c.maxHeight);
        return ClipRRect(
          borderRadius: BorderRadius.circular(Radii.md),
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 9,
              onMapReady: () {
                _mapReady = true;
                _fit(_lastSide);
              },
              onTap: (_, p) => setState(() {
                _draft = _draft.copyWith(lat: p.latitude, lng: p.longitude);
                _pinned = true;
              }),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ru.saasshop.admin',
                tileBuilder: dark ? darkModeTileBuilder : null,
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: center,
                    radius: _draft.radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: (_draft.enabled ? AppColors.brand : Colors.grey)
                        .withValues(alpha: 0.15),
                    borderColor: _draft.enabled ? AppColors.brand : Colors.grey,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on_rounded,
                      size: 44,
                      color: AppColors.lowStock,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black38)],
                    ),
                  ),
                ],
              ),
              const OsmAttribution(),
            ],
          ),
        );
      },
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ограничить доставку радиусом'),
          subtitle: Text(
            _draft.enabled
                ? 'Клиентам дальше радиуса предложим самовывоз'
                : 'Принимаем заказы с любым адресом',
          ),
          value: _draft.enabled,
          onChanged: (v) =>
              setState(() => _draft = _draft.copyWith(enabled: v)),
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _address,
          onChanged: (_) => setState(() => _pinned = false),
          decoration: const InputDecoration(
            labelText: 'Адрес склада / магазина',
            prefixIcon: Icon(Icons.warehouse_outlined),
            helperText: 'Или просто нажмите на карту, чтобы поставить точку',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            Text('Радиус', style: text.titleSmall),
            const Spacer(),
            Text(
              _km(_draft.radiusKm),
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.brand,
              ),
            ),
          ],
        ),
        Slider(
          min: 1,
          max: 100,
          divisions: 99,
          value: _draft.radiusKm.clamp(1, 100),
          label: _km(_draft.radiusKm),
          onChanged: _draft.enabled
              ? (v) => setState(
                  () => _draft = _draft.copyWith(radiusKm: v.roundToDouble()),
                )
              : null,
          onChangeEnd: (_) => _fit(_lastSide),
        ),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final p in _presets)
              ChoiceChip(
                label: Text(_km(p)),
                selected: _draft.radiusKm == p,
                onSelected: _draft.enabled
                    ? (_) {
                        setState(() => _draft = _draft.copyWith(radiusKm: p));
                        _fit(_lastSide);
                      }
                    : null,
              ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        Text(
          'Площадь зоны ≈ ${(pi * _draft.radiusKm * _draft.radiusKm).round()} км²',
          style: text.bodySmall?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: Insets.lg),
        Text('Города, куда возим целиком', style: text.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Доставляем в любую точку этих городов, даже если она дальше радиуса. '
          'Остальные адреса — только внутри круга.',
          style: text.bodySmall?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final c in _draft.cities)
              InputChip(
                label: Text(c),
                avatar: const Icon(Icons.location_city_rounded, size: 16),
                onDeleted: _draft.enabled ? () => _removeCity(c) : null,
              ),
            if (_draft.cities.isEmpty)
              Text(
                'Не выбраны — работает только радиус',
                style: TextStyle(color: palette.textSecondary),
              ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: _city,
          enabled: _draft.enabled,
          onSubmitted: _addCity,
          decoration: InputDecoration(
            hintText: 'Добавить город, например: Химки',
            isDense: true,
            suffixIcon: IconButton(
              tooltip: 'Добавить',
              onPressed: () => _addCity(_city.text),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in _citySuggestions)
              if (!_draft.cities.any((x) => x.toLowerCase() == c.toLowerCase()))
                ActionChip(
                  label: Text('+ $c'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _draft.enabled ? () => _addCity(c) : null,
                ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _dirty && !_busy ? _save : null,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_dirty ? 'Сохранить зону' : 'Сохранено'),
        ),
        const Divider(height: Insets.xl * 2),
        Text('Проверить адрес клиента', style: text.titleSmall),
        const SizedBox(height: Insets.sm),
        TextField(
          controller: _probe,
          onSubmitted: (_) => _check(),
          decoration: InputDecoration(
            hintText: 'Например: Химки, Ленинский пр-т, 1',
            suffixIcon: IconButton(
              tooltip: 'Проверить',
              onPressed: _check,
              icon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
        if (_probeResult case final v?) ...[
          const SizedBox(height: Insets.sm),
          _Verdict(v),
        ],
        if (_dirty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Проверка идёт по сохранённым настройкам',
              style: text.bodySmall?.copyWith(color: palette.textSecondary),
            ),
          ),
      ],
    );

    return AdminCard(
      title: 'Зона доставки',
      subtitle: 'Точка склада и радиус, в котором работают курьеры',
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 820
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: SizedBox(height: 560, child: map)),
                  const SizedBox(width: Insets.xl),
                  Expanded(flex: 2, child: controls),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 320, child: map),
                  const SizedBox(height: Insets.lg),
                  controls,
                ],
              ),
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict(this.v);
  final DeliveryVerdict v;

  @override
  Widget build(BuildContext context) {
    final color = v.ok ? AppColors.fresh : AppColors.lowStock;
    final msg = v.ok
        ? (v.city != null
              ? 'Возим: город «${v.city}» в списке'
              : v.distanceKm == null
              ? 'Проверить не удалось — заказ всё равно примем'
              : 'Возим: ${v.distanceKm!.toStringAsFixed(1)} км от склада')
        : v.reason ?? 'Не возим';
    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            v.ok ? Icons.check_circle_rounded : Icons.block_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: Insets.sm),
          Expanded(child: Text(msg)),
        ],
      ),
    );
  }
}

class _HoursCard extends ConsumerStatefulWidget {
  const _HoursCard({required this.initial});
  final WorkHours initial;

  @override
  ConsumerState<_HoursCard> createState() => _HoursCardState();
}

class _HoursCardState extends ConsumerState<_HoursCard> {
  late WorkHours _saved = widget.initial;
  late WorkHours _draft = widget.initial;
  bool _busy = false;

  bool get _dirty =>
      _draft.start != _saved.start ||
      _draft.end != _saved.end ||
      ([..._draft.days]..sort()).join() != _saved.days.join();

  Future<void> _pickTime({required bool start}) async {
    final current = (start ? _draft.start : _draft.end).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(current[0]),
        minute: int.parse(current[1]),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final v =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(
      () =>
          _draft = start ? _draft.copyWith(start: v) : _draft.copyWith(end: v),
    );
  }

  Future<void> _save() async {
    if (_draft.end.compareTo(_draft.start) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Время закрытия должно быть позже открытия'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(adminRepositoryProvider)
          .saveWorkHours(_draft);
      if (!mounted) return;
      setState(() => _saved = _draft = saved);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Сохранено: ${saved.text}')));
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return AdminCard(
      title: 'Часы работы',
      subtitle: 'Когда принимаем и доставляем заказы — видно на сайте',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final (i, name) in WorkHours.dayNames.indexed)
                FilterChip(
                  label: Text(name),
                  selected: _draft.days.contains(i),
                  onSelected: (on) => setState(
                    () => _draft = _draft.copyWith(
                      days: on
                          ? [..._draft.days, i]
                          : [
                              for (final d in _draft.days)
                                if (d != i) d,
                            ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Wrap(
            spacing: Insets.md,
            runSpacing: Insets.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickTime(start: true),
                icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                label: Text('с ${_draft.start}'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickTime(start: false),
                icon: const Icon(Icons.nightlight_outlined, size: 18),
                label: Text('до ${_draft.end}'),
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Text(
            _draft.days.isEmpty
                ? 'Не выбрано ни одного дня — на сайте будет «временно не работаем»'
                : 'Оплата — при получении: наличными или картой курьеру.',
            style: text.bodySmall?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: Insets.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _dirty && !_busy ? _save : null,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить часы'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialsCard extends ConsumerStatefulWidget {
  const _SocialsCard({required this.initial});
  final ShopSocials initial;

  @override
  ConsumerState<_SocialsCard> createState() => _SocialsCardState();
}

class _SocialsCardState extends ConsumerState<_SocialsCard> {
  late final _telegram = TextEditingController(text: widget.initial.telegram);
  late final _instagram = TextEditingController(text: widget.initial.instagram);
  late ShopSocials _saved = widget.initial;
  bool _busy = false;

  bool get _dirty =>
      _telegram.text.trim() != _saved.telegram ||
      _instagram.text.trim() != _saved.instagram;

  @override
  void dispose() {
    _telegram.dispose();
    _instagram.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(adminRepositoryProvider)
          .saveSocials(
            ShopSocials(
              telegram: _telegram.text.trim(),
              instagram: _instagram.text.trim(),
            ),
          );
      if (!mounted) return;
      setState(() {
        _saved = saved;
        _telegram.text = saved.telegram;
        _instagram.text = saved.instagram;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Соцсети сохранены')));
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.palette.textSecondary);
    return AdminCard(
      title: 'Соцсети',
      subtitle: 'Ссылки в подвале сайта и на странице «Контакты». Пустое поле — не показываем',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _telegram,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Telegram',
              hintText: '@foodtor или https://t.me/foodtor',
              prefixIcon: Icon(Icons.send_rounded),
            ),
          ),
          const SizedBox(height: Insets.md),
          TextField(
            controller: _instagram,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Instagram',
              hintText: '@foodtor или https://instagram.com/foodtor',
              prefixIcon: Icon(Icons.camera_alt_outlined),
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            'Рядом с Instagram на сайте автоматически появится обязательная пометка о Meta.',
            style: muted,
          ),
          const SizedBox(height: Insets.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _dirty && !_busy ? _save : null,
              child: const Text('Сохранить соцсети'),
            ),
          ),
        ],
      ),
    );
  }
}
