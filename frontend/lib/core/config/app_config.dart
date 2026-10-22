/// Параметры сборки (--dart-define). Демо-режим работает без сервера — для показов.
///
///   flutter build web --dart-define=APP_MODE=demo                  # демо, данные внутри приложения
///   flutter build web --dart-define=API_URL=https://shop.ru        # релиз (по умолчанию)
abstract final class AppConfig {
  static const mode = String.fromEnvironment(
    'APP_MODE',
    defaultValue: 'release',
  );
  static bool get isDemo => mode == 'demo';

  /// Пусто → тот же домен, что и сайт (Caddy проксирует /api на бэкенд) — без CORS.
  static const apiUrl = String.fromEnvironment('API_URL');

  /// Правила доставки по умолчанию — для подсказок в корзине; итог всегда пересчитывает сервер.
  static const freeCourierFrom = 1500.0;
  static const courierFee = 199.0;
  static const expressFee = 149.0;

  static const shopName = String.fromEnvironment(
    'SHOP_NAME',
    defaultValue: 'FOODTOR',
  );
  static const supportPhone = String.fromEnvironment(
    'SUPPORT_PHONE',
    defaultValue: '+7 (000) 000-00-00',
  );
  static const supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@example.com',
  );
}
