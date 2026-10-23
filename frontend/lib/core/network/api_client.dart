import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

/// Ошибка API с человекочитаемым сообщением для UI.
class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;

  static ApiException from(Object e) {
    if (e is ApiException) return e;
    if (e is DioException) {
      final data = e.response?.data;
      final detail = data is Map ? data['detail'] : null;
      final msg = switch (detail) {
        final String s => s,
        final List l when l.isNotEmpty =>
          (l.first as Map)['msg']?.toString() ?? 'Проверьте введённые данные',
        _ => switch (e.type) {
          DioExceptionType.connectionError ||
          DioExceptionType.connectionTimeout => 'Нет связи с сервером',
          _ =>
            e.response?.statusCode == 429
                ? 'Слишком много попыток, подождите минуту'
                : 'Ошибка сервера',
        },
      };
      return ApiException(_translate(msg), status: e.response?.statusCode);
    }
    return ApiException('Что-то пошло не так');
  }

  /// Сообщения бэкенда — на английском (контракт API); пользователю — по-русски.
  static String _translate(String m) => switch (m) {
    'Invalid email or password' => 'Неверный email или пароль',
    'Email is already registered' => 'Этот email уже зарегистрирован',
    'Invalid payment method' => 'Выберите способ оплаты',
    'Insufficient permissions' => 'Недостаточно прав',
    // ошибки валидации Pydantic: «Value error, Пароль слишком простой…»
    _ when m.startsWith('Value error, ') => m.substring('Value error, '.length),
    _ when m.startsWith('Not enough stock') =>
      'Товар закончился: ${m.replaceFirst('Not enough stock for ', '')}',
    _ => m,
  };
}

/// Пустой API_URL → тот же домен, что и сайт. Uri.base.origin бросает исключение для file:// (тесты, локальный файл).
String apiBaseUrl() {
  if (AppConfig.apiUrl.isNotEmpty) return AppConfig.apiUrl;
  return Uri.base.scheme.startsWith('http')
      ? Uri.base.origin
      : 'http://localhost:8000';
}

/// Хранилище refresh-токена. Access-токен живёт только в памяти (15 минут) — меньше поверхность XSS.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'refresh_token';

  String? access;

  Future<String?> readRefresh() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null; // в тестах/без поддержки хранилища — сессия просто не восстанавливается
    }
  }

  Future<void> save(String accessToken, String refreshToken) async {
    access = accessToken;
    try {
      await _storage.write(key: _key, value: refreshToken);
    } catch (_) {}
  }

  Future<void> clear() async {
    access = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Сигнал «сессия истекла» — слушают провайдеры авторизации, чтобы разлогинить UI.
class SessionExpiredNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final sessionExpiredProvider = NotifierProvider<SessionExpiredNotifier, int>(
  SessionExpiredNotifier.new,
);

/// Dio с автоподстановкой токена и прозрачным обновлением по 401 (single-flight: один refresh на всех).
final dioProvider = Provider<Dio>((ref) {
  final tokens = ref.watch(tokenStoreProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl(),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
    ),
  );
  Future<bool>? refreshing;

  Future<bool> doRefresh() async {
    final refresh = await tokens.readRefresh();
    if (refresh == null) return false;
    try {
      final r = await Dio(BaseOptions(baseUrl: dio.options.baseUrl))
          .post<Map<String, dynamic>>(
            '/api/v1/auth/refresh',
            data: {'refresh_token': refresh},
          );
      await tokens.save(
        r.data!['access_token'] as String,
        r.data!['refresh_token'] as String,
      );
      return true;
    } catch (_) {
      await tokens.clear();
      ref.read(sessionExpiredProvider.notifier).bump();
      return false;
    }
  }

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (tokens.access case final t?) {
          options.headers['Authorization'] = 'Bearer $t';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final retried = e.requestOptions.extra['retried'] == true;
        if (e.response?.statusCode != 401 ||
            retried ||
            e.requestOptions.path.contains('/auth/')) {
          return handler.next(e);
        }
        final ok = await (refreshing ??= doRefresh().whenComplete(
          () => refreshing = null,
        ));
        if (!ok) return handler.next(e);
        final opts = e.requestOptions
          ..extra['retried'] = true
          ..headers['Authorization'] = 'Bearer ${tokens.access}';
        try {
          handler.resolve(await dio.fetch(opts));
        } on DioException catch (err) {
          handler.next(err);
        }
      },
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(requestBody: false, responseBody: false),
    );
  }
  return dio;
});

/// Восстановление сессии при старте: refresh-токен → новая пара.
Future<bool> restoreSession(Ref ref) async {
  final tokens = ref.read(tokenStoreProvider);
  final refresh = await tokens.readRefresh();
  if (refresh == null) return false;
  try {
    final dio = ref.read(dioProvider);
    final r = await dio.post<Map<String, dynamic>>(
      '/api/v1/auth/refresh',
      data: {'refresh_token': refresh},
    );
    await tokens.save(
      r.data!['access_token'] as String,
      r.data!['refresh_token'] as String,
    );
    return true;
  } catch (_) {
    await tokens.clear();
    return false;
  }
}

/// POST /auth/login (OAuth2 form) → сохраняет токены.
Future<void> loginWithPassword(Ref ref, String email, String password) async {
  try {
    final r = await ref
        .read(dioProvider)
        .post<Map<String, dynamic>>(
          '/api/v1/auth/login',
          data: {'username': email.trim(), 'password': password},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
    await ref
        .read(tokenStoreProvider)
        .save(
          r.data!['access_token'] as String,
          r.data!['refresh_token'] as String,
        );
  } catch (e) {
    throw ApiException.from(e);
  }
}

/// Смена пароля: сервер разлогинивает остальные устройства и выдаёт этому новую пару токенов.
Future<void> changePasswordSession(Ref ref, String current, String next) async {
  try {
    final r = await ref
        .read(dioProvider)
        .post<Map<String, dynamic>>(
          '/api/v1/auth/change-password',
          data: {'current_password': current, 'new_password': next},
        );
    await ref
        .read(tokenStoreProvider)
        .save(
          r.data!['access_token'] as String,
          r.data!['refresh_token'] as String,
        );
  } catch (e) {
    throw ApiException.from(e);
  }
}

/// «Выйти на всех устройствах»: все токены аккаунта становятся недействительными.
Future<void> logoutEverywhere(Ref ref) async {
  try {
    await ref.read(dioProvider).post<dynamic>('/api/v1/auth/logout-all');
  } catch (e) {
    throw ApiException.from(e);
  } finally {
    await ref.read(tokenStoreProvider).clear();
  }
}

Future<void> logoutSession(Ref ref) async {
  final tokens = ref.read(tokenStoreProvider);
  final refresh = await tokens.readRefresh();
  if (refresh != null) {
    unawaited(
      ref
          .read(dioProvider)
          .post('/api/v1/auth/logout', data: {'refresh_token': refresh})
          .catchError((_) => Response(requestOptions: RequestOptions())),
    );
  }
  await tokens.clear();
}
