import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef Handler = Object? Function(RequestOptions req);

/// Фейковый сервер для релизных тестов: маршруты «METHOD /path» → JSON (или (status, json)).
class FakeApi implements HttpClientAdapter {
  FakeApi(this.routes);
  final Map<String, Handler> routes;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.uri.path}';
    calls.add(key);
    final handler = routes[key];
    if (handler == null) return _json(404, {'detail': 'Not Found: $key'});
    final result = handler(options);
    return result is (int, Object?)
        ? _json(result.$1, result.$2)
        : _json(200, result);
  }

  ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> price(String p, {String? compareAt}) => {
  'price': p,
  'retail_price': p,
  'compare_at_price': compareAt,
  'is_wholesale': false,
  'source': 'retail',
  'tiers': <Object>[],
};

Map<String, dynamic> product(
  int id,
  String name,
  String p, {
  List<String> badges = const [],
  int? stockLeft,
}) => {
  'id': id,
  'sku': 'SKU-$id',
  'name': name,
  'image_url': null,
  'in_stock': true,
  'price': price(p),
  'brand': 'Ферма',
  'unit': '1 кг',
  'category_id': 1,
  'badges': badges,
  'stock_left': stockLeft,
  'attributes': {'Страна': 'Россия'},
  'rating': 4.8,
  'reviews_count': 3,
};

/// DioException с телом {"detail": ...} — как ответ FastAPI.
abstract final class DioExceptionShim {
  static DioException withDetail(int status, String detail) {
    final req = RequestOptions(path: '/x');
    return DioException(
      requestOptions: req,
      response: Response(
        requestOptions: req,
        statusCode: status,
        data: {'detail': detail},
      ),
      type: DioExceptionType.badResponse,
    );
  }
}
