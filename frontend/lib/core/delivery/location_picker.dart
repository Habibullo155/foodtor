import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import 'delivery_check.dart';

class PickedLocation {
  const PickedLocation(this.lat, this.lng, this.address);
  final double lat;
  final double lng;
  final String? address; // подпись по геокодеру; null — покупатель допишет сам
}

/// Полноэкранный выбор точки: карта двигается под булавкой в центре.
/// Кнопка «Моё местоположение», круг зоны доставки и сразу ответ «возим / не возим».
Future<PickedLocation?> showLocationPicker(
  BuildContext context, {
  double? lat,
  double? lng,
}) => Navigator.of(context).push<PickedLocation>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _LocationPicker(lat: lat, lng: lng),
  ),
);

class _LocationPicker extends ConsumerStatefulWidget {
  const _LocationPicker({this.lat, this.lng});
  final double? lat;
  final double? lng;

  @override
  ConsumerState<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends ConsumerState<_LocationPicker> {
  final _map = MapController();
  DeliveryZoneInfo? _zone;
  late LatLng _point = LatLng(widget.lat ?? 55.7558, widget.lng ?? 37.6176);
  String? _address;
  DeliveryVerdict? _verdict;
  bool _resolving = false;
  bool _locating = false;
  Timer? _debounce;
  int _request = 0; // отбрасываем ответы для старых точек

  DeliveryChecker get _checker => ref.read(deliveryCheckerProvider);

  @override
  void initState() {
    super.initState();
    _checker.zone().then((z) {
      if (!mounted || z == null) return;
      setState(() => _zone = z);
      if (widget.lat == null) _moveTo(LatLng(z.lat, z.lng), zoom: 11);
    });
    _resolve();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _moveTo(LatLng p, {double? zoom}) {
    _point = p;
    try {
      _map.move(p, zoom ?? _map.camera.zoom);
    } catch (_) {} // карта ещё не готова — начальная точка уже в _point
    _resolve();
  }

  /// После остановки карты: адрес по точке и проверка зоны (с паузой, чтобы не дёргать геокодер).
  void _resolve() {
    _debounce?.cancel();
    setState(() => _resolving = true);
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final id = ++_request;
      final p = _point;
      final results = await Future.wait([
        _checker.reverse(p.latitude, p.longitude),
        _checker.checkPoint(p.latitude, p.longitude),
      ]);
      if (!mounted || id != _request) return;
      setState(() {
        _address = results[0] as String?;
        _verdict = results[1] as DeliveryVerdict;
        _resolving = false;
      });
    });
  }

  Future<void> _myLocation() async {
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Геолокация выключена на устройстве';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Разрешите сайту доступ к местоположению в настройках браузера';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      _moveTo(LatLng(pos.latitude, pos.longitude), zoom: 16);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось определить местоположение: $e')),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final zone = _zone;
    final v = _verdict;
    final outside = v != null && !v.ok;

    return Scaffold(
      appBar: AppBar(title: const Text('Куда доставить')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _point,
              initialZoom: widget.lat != null ? 16 : 11,
              onPositionChanged: (camera, hasGesture) {
                if (!hasGesture) return;
                _point = camera.center;
                _resolve();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ru.saasshop.shop',
                tileBuilder: dark ? darkModeTileBuilder : null,
              ),
              if (zone != null && zone.enabled)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(zone.lat, zone.lng),
                      radius: zone.radiusKm * 1000,
                      useRadiusInMeter: true,
                      color: AppColors.brand.withValues(alpha: 0.08),
                      borderColor: AppColors.brand.withValues(alpha: 0.6),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              const OsmAttribution(),
            ],
          ),
          // Булавка в центре: точка доставки — то, что под её остриём
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 44),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 48,
                  color: outside ? palette.textSecondary : AppColors.lowStock,
                  shadows: const [Shadow(blurRadius: 8, color: Colors.black38)],
                ),
              ),
            ),
          ),
          Positioned(
            right: Insets.lg,
            bottom: 200,
            child: FloatingActionButton.extended(
              heroTag: 'my-location',
              onPressed: _locating ? null : _myLocation,
              icon: _locating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded),
              label: const Text('Моё местоположение'),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: palette.surface,
              elevation: 8,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Radii.lg),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(Insets.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _resolving && _address == null
                            ? 'Определяем адрес…'
                            : _address ??
                                  'Адрес не определён — уточните его в форме',
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if (_resolving)
                        const LinearProgressIndicator(minHeight: 2)
                      else if (v != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              v.ok
                                  ? Icons.check_circle_rounded
                                  : Icons.wrong_location_outlined,
                              size: 18,
                              color: v.ok
                                  ? AppColors.fresh
                                  : AppColors.lowStock,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                v.ok
                                    ? (v.distanceKm == null
                                          ? 'Сюда доставляем'
                                          : 'Сюда доставляем · ${v.distanceKm!.toStringAsFixed(1)} км от склада')
                                    : 'Мы не доставляем по вашему адресу. ${v.reason ?? ''}',
                                style: TextStyle(
                                  color: v.ok ? null : AppColors.lowStock,
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: Insets.md),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: _resolving || outside
                            ? null
                            : () => Navigator.pop(
                                context,
                                PickedLocation(
                                  _point.latitude,
                                  _point.longitude,
                                  _address,
                                ),
                              ),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          outside ? 'Сюда не доставляем' : 'Доставить сюда',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Подпись «© OpenStreetMap» (обязательна по лицензии) — компактная, не ломает узкую вёрстку.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '© OpenStreetMap',
        style: TextStyle(fontSize: 10, color: Colors.black87),
      ),
    ),
  );
}
