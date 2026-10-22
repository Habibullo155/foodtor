import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../network/api_client.dart';

/// Результат проверки адреса: возим ли туда и сколько км от склада.
class DeliveryVerdict {
  const DeliveryVerdict({
    required this.ok,
    this.distanceKm,
    this.radiusKm,
    this.reason,
    this.city,
  });

  /// Проверить не удалось (сеть/геокодер) — не мешаем оформить, финально решит сервер.
  static const unknown = DeliveryVerdict(ok: true);

  final bool ok;
  final double? distanceKm;
  final double? radiusKm;
  final String? reason;
  final String? city; // адрес подошёл по списку городов

  /// Адрес неполный/не найден — не «не возим», а «уточните» (предлагаем карту, а не самовывоз).
  bool get needsDetails =>
      !ok &&
      (reason?.contains('номер дома') == true ||
          reason?.startsWith('Не нашли') == true);

  factory DeliveryVerdict.fromJson(Map<String, dynamic> j) => DeliveryVerdict(
    ok: j['ok'] as bool,
    distanceKm: (j['distance_km'] as num?)?.toDouble(),
    radiusKm: (j['radius_km'] as num?)?.toDouble(),
    reason: j['reason'] as String?,
    city: j['city'] as String?,
  );
}

class DeliveryZoneInfo {
  const DeliveryZoneInfo({
    required this.lat,
    required this.lng,
    required this.radiusKm,
    this.enabled = true,
    this.cities = const [],
  });
  final double lat;
  final double lng;
  final double radiusKm;
  final bool enabled;
  final List<String> cities;

  factory DeliveryZoneInfo.fromJson(Map<String, dynamic> j) => DeliveryZoneInfo(
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    radiusKm: (j['radius_km'] as num).toDouble(),
    enabled: j['enabled'] as bool? ?? true,
    cities: [...?(j['cities'] as List?)?.cast<String>()],
  );
}

const needHouseMessage =
    'Укажите улицу и номер дома — или выберите точку на карте';

final _house = RegExp(
  r'(?<![\wа-яё])\d+[а-яa-z]?(?:\s*[/к]\s*\d+)?(?![\wа-яё])',
  caseSensitive: false,
);

const _notStreet = {
  'москва', 'город', 'россия', 'область', 'дом', 'корпус', 'строение', //
  'квартира', 'подъезд', 'этаж',
};

/// Та же проверка, что на сервере: номер дома + хотя бы одно слово, кроме названия города.
/// «Москва» и «Москва, 5» — не адрес; «Ленинский пр-т, 39/1» — адрес.
String? addressProblem(String address, {Iterable<String> cities = const []}) {
  final t = address.trim().toLowerCase().replaceAll('ё', 'е');
  if (!_house.hasMatch(t)) return needHouseMessage;
  final skip = {
    ..._notStreet,
    for (final c in cities) c.toLowerCase().replaceAll('ё', 'е'),
    ...DemoDeliveryChecker.places.keys,
  };
  final hasStreet = RegExp(r'[а-яa-z]{3,}')
      .allMatches(t)
      .any((m) => !skip.contains(m[0]));
  return hasStreet ? null : needHouseMessage;
}

abstract interface class DeliveryChecker {
  Future<DeliveryVerdict> check(String address);

  /// Проверка по точке на карте — точнее, чем по строке адреса.
  Future<DeliveryVerdict> checkPoint(double lat, double lng);

  /// Точка → «Москва, Тверская улица, 12» (null — не удалось определить).
  Future<String?> reverse(double lat, double lng);

  Future<DeliveryZoneInfo?> zone();
}

final deliveryCheckerProvider = Provider<DeliveryChecker>(
  (ref) => AppConfig.isDemo
      ? DemoDeliveryChecker()
      : HttpDeliveryChecker(ref.read(dioProvider)),
);

/// POST /delivery/check — тот же расчёт, что и при оформлении заказа на сервере.
class HttpDeliveryChecker implements DeliveryChecker {
  HttpDeliveryChecker(this._dio);
  final Dio _dio;
  final _cache = <String, DeliveryVerdict>{};

  @override
  Future<DeliveryVerdict> check(String address) async {
    final key = address.trim().toLowerCase();
    if (_cache[key] case final v?) return v;
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/api/v1/delivery/check',
        data: {'address': address.trim()},
      );
      return _cache[key] = DeliveryVerdict.fromJson(r.data!);
    } catch (_) {
      return DeliveryVerdict.unknown;
    }
  }

  @override
  Future<DeliveryVerdict> checkPoint(double lat, double lng) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/api/v1/delivery/check',
        data: {'lat': lat, 'lng': lng},
      );
      return DeliveryVerdict.fromJson(r.data!);
    } catch (_) {
      return DeliveryVerdict.unknown;
    }
  }

  @override
  Future<String?> reverse(double lat, double lng) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        '/api/v1/delivery/reverse',
        queryParameters: {'lat': lat, 'lng': lng},
      );
      return r.data!['address'] as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DeliveryZoneInfo?> zone() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/v1/delivery/zone');
      return DeliveryZoneInfo.fromJson(r.data!);
    } catch (_) {
      return null;
    }
  }
}

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a =
      pow(sin(dLat / 2), 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLng / 2), 2);
  return 2 * r * asin(sqrt(a));
}

/// Демо без сервера: маленький справочник городов вокруг Москвы.
/// Адрес без города считаем московским. Зону меняет демо-админка (в одной вкладке).
class DemoDeliveryChecker implements DeliveryChecker {
  static double centerLat = 55.7539, centerLng = 37.6208, radiusKm = 20;
  static bool enabled = true;
  static List<String> cities = const ['Москва'];

  static const places = {
    'зеленоград': (55.9825, 37.1814),
    'химки': (55.8897, 37.4450),
    'мытищи': (55.9116, 37.7308),
    'люберцы': (55.6763, 37.8981),
    'балашиха': (55.7963, 37.9382),
    'красногорск': (55.8204, 37.3302),
    'одинцово': (55.6789, 37.2638),
    'подольск': (55.4311, 37.5447),
    'королёв': (55.9162, 37.8545),
    'королев': (55.9162, 37.8545),
    'домодедово': (55.4363, 37.7666),
    'сергиев посад': (56.3153, 38.1358),
    'коломна': (55.0794, 38.7783),
    'тула': (54.1931, 37.6177),
    'калуга': (54.5138, 36.2612),
    'тверь': (56.8587, 35.9176),
    'рязань': (54.6292, 39.7364),
    'владимир': (56.1290, 40.4066),
    'санкт-петербург': (59.9386, 30.3141),
    'петербург': (59.9386, 30.3141),
    'казань': (55.7963, 49.1088),
    'нижний новгород': (56.3269, 44.0059),
    'екатеринбург': (56.8389, 60.6057),
  };

  @override
  Future<DeliveryVerdict> check(String address) async {
    if (!enabled) return DeliveryVerdict.unknown;
    if (addressProblem(address, cities: cities) case final p?) {
      return DeliveryVerdict(ok: false, radiusKm: radiusKm, reason: p);
    }
    final q = address.toLowerCase().replaceAll('ё', 'е');
    final words = RegExp(r'[a-zа-я0-9-]+')
        .allMatches(q)
        .map((m) => m[0])
        .toSet();
    for (final c in cities) {
      final city = c.toLowerCase().replaceAll('ё', 'е');
      if (words.contains(city) || (city.contains(' ') && q.contains(city))) {
        return DeliveryVerdict(
          ok: true,
          distanceKm: 0,
          radiusKm: radiusKm,
          city: c,
        );
      }
    }
    var point = (55.7558, 37.6176); // по умолчанию — Москва, район центра
    for (final MapEntry(:key, :value) in places.entries) {
      if (q.contains(key)) point = value;
    }
    if (point == (55.7558, 37.6176)) {
      // «ул. Профсоюзная, 3» → стабильная точка в пределах МКАД
      final h = q.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0xFFFF);
      point = (
        55.7558 + (h % 200 - 100) / 1000,
        37.6176 + (h ~/ 200 % 200 - 100) / 700,
      );
    }
    return checkPoint(point.$1, point.$2);
  }

  @override
  Future<DeliveryVerdict> checkPoint(double lat, double lng) async {
    if (!enabled) return DeliveryVerdict.unknown;
    final d = haversineKm(centerLat, centerLng, lat, lng);
    final km = (d * 10).round() / 10;
    return DeliveryVerdict(
      ok: d <= radiusKm,
      distanceKm: km,
      radiusKm: radiusKm,
      reason: d <= radiusKm
          ? null
          : 'Мы не доставляем по этому адресу: ${km.toStringAsFixed(0)} км от нас, '
                'а доставляем в радиусе ${radiusKm.toStringAsFixed(0)} км'
                '${cities.isEmpty ? '' : ' и по городам: ${cities.join(', ')}'}. Можно выбрать самовывоз.',
    );
  }

  /// Демо без геокодера: ближайший город из справочника + координаты точки.
  @override
  Future<String?> reverse(double lat, double lng) async {
    var best = 'Москва';
    var bestKm = haversineKm(lat, lng, 55.7558, 37.6176);
    for (final MapEntry(:key, :value) in places.entries) {
      final km = haversineKm(lat, lng, value.$1, value.$2);
      if (km < bestKm) (best, bestKm) = (key, km);
    }
    final city = best[0].toUpperCase() + best.substring(1);
    return '$city, точка на карте (${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})';
  }

  @override
  Future<DeliveryZoneInfo?> zone() async => DeliveryZoneInfo(
    lat: centerLat,
    lng: centerLng,
    radiusKm: radiusKm,
    enabled: enabled,
    cities: cities,
  );
}
