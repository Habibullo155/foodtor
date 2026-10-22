import 'package:flutter/material.dart';

@immutable
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.imageUrl,
  });
  final int id;
  final String name;
  final IconData icon; // для компактных списков (сайдбар)
  final Color color;
  final String? imageUrl; // картинка для карусели

  /// Цвета плиток для категорий из API (у них нет своего цвета) — по кругу.
  static const _palette = [
    Color(0xFF16A34A),
    Color(0xFFF97316),
    Color(0xFFE11D48),
    Color(0xFF65A30D),
    Color(0xFFCA8A04),
    Color(0xFFD97706),
    Color(0xFF0891B2),
    Color(0xFF7C3AED),
  ];

  factory Category.fromJson(Map<String, dynamic> j, int index) => Category(
    id: j['id'] as int,
    name: j['name'] as String,
    icon: Icons.category_outlined,
    color: _palette[index % _palette.length],
    imageUrl: j['image_url'] as String?,
  );
}

enum ProductBadge {
  hit('Хит'),
  fresh('Новинка'),
  lowStock('Осталось мало');

  const ProductBadge(this.label);
  final String label;
}

enum DeliveryMethod {
  courier('Курьер', Icons.local_shipping_outlined),
  pickup('Пункт выдачи', Icons.storefront_outlined),
  express('Экспресс за 2 часа', Icons.bolt_rounded);

  const DeliveryMethod(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Вариант доставки — рассчитывается бэкендом по адресу/региону пользователя.
@immutable
class DeliveryOption {
  const DeliveryOption({
    required this.method,
    required this.minDays,
    required this.maxDays,
    required this.price,
  });
  final DeliveryMethod method;
  final int minDays;
  final int maxDays;
  final double price; // 0 = бесплатно

  bool get isFree => price == 0;

  /// «Сегодня», «Завтра», «2–3 дня».
  String get eta => switch ((minDays, maxDays)) {
    (0, 0) => 'Сегодня',
    (1, 1) => 'Завтра',
    (final a, final b) when a == b => '$a дн.',
    (final a, final b) => '$a–$b дн.',
  };

  factory DeliveryOption.fromJson(Map<String, dynamic> j) => DeliveryOption(
    method: DeliveryMethod.values.byName(j['method'] as String),
    minDays: j['min_days'] as int,
    maxDays: j['max_days'] as int,
    price: double.parse(j['price'].toString()),
  );
}
