import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Модели админки — не зависят от источника данных (демо или API).

enum OrderStage {
  newOrder('new', 'Новый', Icons.fiber_new_rounded, Color(0xFF6366F1)),
  picking('picking', 'В сборке', Icons.inventory_2_outlined, Color(0xFFF59E0B)),
  shipped(
    'shipped',
    'Отправлен',
    Icons.local_shipping_outlined,
    Color(0xFF0EA5E9),
  ),
  delivered(
    'delivered',
    'Доставлен',
    Icons.check_circle_outline_rounded,
    Color(0xFF10B981),
  ),
  cancelled('cancelled', 'Отменён', Icons.cancel_outlined, Color(0xFF9CA3AF));

  const OrderStage(this.code, this.label, this.icon, this.color);
  final String code;
  final String label;
  final IconData icon;
  final Color color;

  static OrderStage parse(String c) =>
      values.firstWhere((s) => s.code == c, orElse: () => newOrder);

  /// Конечный автомат — как ORDER_TRANSITIONS на бэкенде.
  List<OrderStage> get next => switch (this) {
    newOrder => [picking, cancelled],
    picking => [shipped, cancelled],
    shipped => [delivered],
    delivered || cancelled => [],
  };
}

double _d(Object? v) => v == null ? 0 : double.parse(v.toString());

@immutable
class OrderLine {
  const OrderLine({
    required this.name,
    required this.qty,
    this.productId,
    this.unit,
    this.imageUrl,
    this.price = 0,
    this.cost = 0,
    this.picked = false,
  });

  final int? productId;
  final String name;
  final String? unit;
  final String? imageUrl;
  final int qty;
  final double price; // за единицу
  final double cost; // себестоимость за единицу
  final bool picked;

  double get total => price * qty;
  double get costTotal => cost * qty;
  OrderLine copyWith({bool? picked}) => OrderLine(
    productId: productId,
    name: name,
    unit: unit,
    imageUrl: imageUrl,
    qty: qty,
    price: price,
    cost: cost,
    picked: picked ?? this.picked,
  );
}

/// Что с деньгами по заказу — одна метка для таблицы, карточки и сборки.
enum PaymentState {
  paidOnline('Оплачен онлайн', Icons.credit_card_rounded, Color(0xFF16A34A)),
  awaiting('Ждём оплату', Icons.hourglass_top_rounded, Color(0xFFD97706)),
  failed('Оплата не прошла', Icons.credit_card_off_rounded, Color(0xFFDC2626)),
  refunded('Возврат', Icons.undo_rounded, Color(0xFF64748B)),
  onDelivery('При получении', Icons.payments_outlined, Color(0xFF2563EB)),
  paidOnDelivery(
    'Оплачен при получении',
    Icons.payments_rounded,
    Color(0xFF16A34A),
  );

  const PaymentState(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;

  /// Онлайн-заказ нельзя собирать, пока банк не подтвердил оплату.
  bool get blocksPicking => this == awaiting || this == failed;

  static PaymentState of(String method, String status) =>
      switch ((method, status)) {
        (_, 'refunded') => refunded,
        ('card_online', 'paid') => paidOnline,
        ('card_online', 'failed') => failed,
        ('card_online', _) => awaiting,
        (_, 'paid') => paidOnDelivery,
        _ => onDelivery,
      };
}

@immutable
class AdminOrder {
  const AdminOrder({
    required this.id,
    required this.number,
    required this.customer,
    required this.address,
    required this.createdAt,
    required this.stage,
    required this.lines,
    this.isB2B = false,
    this.comment,
    this.phone = '',
    this.total = 0,
    this.cost = 0,
    this.delivery = 0,
    this.paymentStatus = 'not_required',
    this.paymentMethod = 'cash',
  });

  final int id;
  final String number;
  final String customer;
  final String phone;
  final String address;
  final DateTime createdAt;
  final OrderStage stage;
  final List<OrderLine> lines;
  final bool isB2B;
  final String? comment;
  final double total;
  final double cost;
  final double delivery; // наши расходы на доставку/эквайринг
  final String paymentStatus;
  final String paymentMethod;

  double get profit => total - cost - delivery;
  int get itemsCount => lines.fold(0, (a, l) => a + l.qty);
  double get pickedShare =>
      lines.isEmpty ? 0 : lines.where((l) => l.picked).length / lines.length;
  bool get isPaidOnline => paymentStatus == 'paid';
  PaymentState get payment => PaymentState.of(paymentMethod, paymentStatus);

  AdminOrder copyWith({
    OrderStage? stage,
    List<OrderLine>? lines,
    String? paymentStatus,
  }) => AdminOrder(
    id: id,
    number: number,
    customer: customer,
    phone: phone,
    address: address,
    createdAt: createdAt,
    stage: stage ?? this.stage,
    lines: lines ?? this.lines,
    isB2B: isB2B,
    comment: comment,
    total: total,
    cost: cost,
    delivery: delivery,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    paymentMethod: paymentMethod,
  );

  /// GET /admin/orders (полные данные) и GET /staff/picking (без цен) — один парсер.
  factory AdminOrder.fromJson(Map<String, dynamic> j) {
    final items = (j['items'] as List).cast<Map<String, dynamic>>();
    final total = _d(j['total']);
    final cost = _d(j['cost_total']);
    final profit = j['profit'] == null ? null : _d(j['profit']);
    return AdminOrder(
      id: j['id'] as int,
      number: j['number'] as String,
      customer: j['customer_name'] as String? ?? '',
      phone: j['customer_phone'] as String? ?? '',
      address: j['address'] as String? ?? '',
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      stage: OrderStage.parse(j['status'] as String),
      isB2B: j['segment'] == 'b2b',
      comment: (j['note'] ?? j['customer_note']) as String?,
      total: total,
      cost: cost,
      delivery: profit == null ? 0 : total - cost - profit,
      paymentStatus: j['payment_status'] as String? ?? 'not_required',
      paymentMethod: j['payment_method'] as String? ?? 'cash',
      lines: [
        for (final i in items)
          OrderLine(
            productId: i['product_id'] as int?,
            name: i['name'] as String,
            unit: i['unit'] as String?,
            imageUrl: i['image_url'] as String?,
            qty: i['quantity'] as int,
            price: _d(i['unit_price']),
          ),
      ],
    );
  }
}

@immutable
class DayFinance {
  const DayFinance(this.day, this.revenue, this.expenses, this.orders);
  final DateTime day;
  final double revenue;
  final double expenses; // себестоимость + доставка + операционные
  final int orders;
  double get profit => revenue - expenses;
}

@immutable
class FinanceData {
  const FinanceData(this.days, {this.profitVisible = true});
  final List<DayFinance> days; // 2×период: прошлый + текущий
  final bool profitVisible; // false — у роли нет finance:view
}

@immutable
class AdminCategory {
  const AdminCategory(this.id, this.name, [String? slug, this.imageUrl])
    : _slug = slug;
  final int id;
  final String name;
  final String? _slug;
  final String? imageUrl;

  String get slug => _slug ?? slugify(name);
  String get url => '/catalog/$slug';

  AdminCategory copyWith({
    String? name,
    String? imageUrl,
    bool clearImage = false,
  }) => AdminCategory(
    id,
    name ?? this.name,
    _slug,
    clearImage ? null : (imageUrl ?? this.imageUrl),
  );
}

const _tr = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'e',
  'ж': 'zh',
  'з': 'z',
  'и': 'i', //
  'й': 'y',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'h',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'sch',
  'ъ': '',
  'ы': 'y',
  'ь': '',
  'э': 'e', 'ю': 'yu', 'я': 'ya',
};

/// «Крупы и бобовые» → krupy-i-bobovye (как на сервере, app/web/catalog.slugify).
String slugify(String text) {
  final s = text.toLowerCase().split('').map((c) => _tr[c] ?? c).join();
  final slug = s
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty
      ? 'tovar'
      : (slug.length > 80 ? slug.substring(0, 80) : slug);
}

@immutable
class AdminProduct {
  const AdminProduct({
    required this.id,
    required this.sku,
    required this.name,
    required this.price,
    required this.cost,
    required this.stock,
    this.wholesalePrice,
    this.unit,
    this.brand,
    this.imageUrl,
    this.categoryId,
    this.isActive = true,
    this.isHit = false,
    this.description = '',
  });

  final int id;
  final String sku;
  final String name;
  final String? unit;
  final String? brand;
  final String? imageUrl;
  final int? categoryId;
  final double price;
  final double cost;
  final double? wholesalePrice; // видят только подтверждённые оптовики
  final int stock;
  final bool isActive;
  final bool isHit;
  final String description;

  double get marginPercent => price == 0 ? 0 : (price - cost) / price * 100;

  factory AdminProduct.fromJson(Map<String, dynamic> j) => AdminProduct(
    id: j['id'] as int,
    sku: j['sku'] as String,
    name: j['name'] as String,
    unit: j['unit'] as String?,
    brand: j['brand'] as String?,
    imageUrl: j['image_url'] as String?,
    categoryId: j['category_id'] as int?,
    price: _d(j['retail_price']),
    cost: _d(j['cost_price']),
    wholesalePrice: j['wholesale_price'] == null
        ? null
        : _d(j['wholesale_price']),
    stock: j['stock'] as int,
    isActive: j['is_active'] as bool? ?? true,
    isHit: j['is_hit'] as bool? ?? false,
    description: j['description'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'sku': sku,
    'name': name,
    'description': description,
    'unit': unit,
    'brand': brand,
    'category_id': categoryId,
    'cost_price': cost.toStringAsFixed(2),
    'retail_price': price.toStringAsFixed(2),
    'wholesale_price': wholesalePrice?.toStringAsFixed(2),
    'stock': stock,
    'is_active': isActive,
    'is_hit': isHit,
    if (imageUrl != null &&
        (imageUrl!.startsWith('http') || imageUrl!.startsWith('/media/')))
      'image_url': imageUrl,
  };
}

enum ReviewState { pending, approved, rejected }

@immutable
class AdminReview {
  const AdminReview({
    required this.id,
    required this.author,
    required this.productName,
    required this.rating,
    required this.text,
    required this.state,
    this.productImage,
    this.createdAt,
  });

  final int id;
  final String author;
  final String productName;
  final DateTime? createdAt;
  final String? productImage;
  final int rating;
  final String text;
  final ReviewState state;

  AdminReview withState(ReviewState s) => AdminReview(
    id: id,
    author: author,
    productName: productName,
    productImage: productImage,
    rating: rating,
    text: text,
    state: s,
    createdAt: createdAt,
  );

  factory AdminReview.fromJson(Map<String, dynamic> j) => AdminReview(
    id: j['id'] as int,
    author: j['author'] as String,
    productName: j['product_name'] as String,
    productImage: j['product_image'] as String?,
    rating: j['rating'] as int,
    text: j['text'] as String,
    state: ReviewState.values.byName(j['status'] as String),
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
  );
}

@immutable
class TierConfig {
  const TierConfig(
    this.name,
    this.threshold,
    this.percent,
    this.color,
    this.customers, {
    this.id,
  });
  final int? id;
  final String name;
  final double threshold;
  final double percent;
  final Color color;
  final int customers;

  factory TierConfig.fromJson(Map<String, dynamic> j) => TierConfig(
    j['name'] as String,
    _d(j['min_total_spent']),
    _d(j['discount_value']),
    Color(
      int.parse((j['color_hex'] as String).substring(1), radix: 16) |
          0xFF000000,
    ),
    j['customers'] as int? ?? 0,
    id: j['id'] as int,
  );
}

@immutable
class StaffMember {
  const StaffMember({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.isActive = true,
  });
  final int id;
  final String email;
  final String name;
  final String role; // owner | manager | picker
  final bool isActive;

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
    id: j['id'] as int,
    email: j['email'] as String,
    name: j['full_name'] as String,
    role: j['role'] as String,
    isActive: j['is_active'] as bool? ?? true,
  );
}

/// Зона доставки: точка склада + радиус. Клиентам за пределами круга доставку не предлагаем.
@immutable
class DeliveryZone {
  const DeliveryZone({
    required this.enabled,
    required this.storeAddress,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    this.cities = const [],
  });

  /// Центр Москвы — точка по умолчанию, пока владелец не указал свой склад.
  static const moscow = DeliveryZone(
    enabled: true,
    storeAddress: 'Москва, Красная площадь',
    lat: 55.7539,
    lng: 37.6208,
    radiusKm: 20,
    cities: ['Москва'],
  );

  final bool enabled;
  final String storeAddress;
  final double lat;
  final double lng;
  final double radiusKm;

  /// Города, куда возим целиком — даже за пределами радиуса.
  final List<String> cities;

  DeliveryZone copyWith({
    List<String>? cities,
    bool? enabled,
    String? storeAddress,
    double? lat,
    double? lng,
    double? radiusKm,
  }) => DeliveryZone(
    enabled: enabled ?? this.enabled,
    storeAddress: storeAddress ?? this.storeAddress,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    radiusKm: radiusKm ?? this.radiusKm,
    cities: cities ?? this.cities,
  );

  factory DeliveryZone.fromJson(Map<String, dynamic> j) => DeliveryZone(
    enabled: j['enabled'] as bool,
    storeAddress: j['store_address'] as String,
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    radiusKm: (j['radius_km'] as num).toDouble(),
    cities: [...?(j['cities'] as List?)?.cast<String>()],
  );
}

/// Часы работы магазина и доставки. Дни: 0 — понедельник … 6 — воскресенье.
@immutable
class WorkHours {
  const WorkHours({
    required this.days,
    required this.start,
    required this.end,
    this.text = '',
  });

  static const standard = WorkHours(
    days: [0, 1, 2, 3, 4, 5],
    start: '10:00',
    end: '22:00',
    text: 'Пн–Сб с 10:00 до 22:00',
  );
  static const dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  final List<int> days;
  final String start;
  final String end;
  final String text;

  factory WorkHours.fromJson(Map<String, dynamic> j) => WorkHours(
    days: (j['days'] as List).cast<int>(),
    start: j['start'] as String,
    end: j['end'] as String,
    text: j['text'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'days': days, 'start': start, 'end': end};

  WorkHours copyWith({List<int>? days, String? start, String? end}) =>
      WorkHours(
        days: days ?? this.days,
        start: start ?? this.start,
        end: end ?? this.end,
      );
}

@immutable
class ShopSocials {
  const ShopSocials({this.telegram = '', this.instagram = ''});
  final String telegram;
  final String instagram;

  factory ShopSocials.fromJson(Map<String, dynamic> j) => ShopSocials(
    telegram: j['telegram'] as String? ?? '',
    instagram: j['instagram'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'telegram': telegram,
    'instagram': instagram,
  };
}

enum B2BStatus {
  pending('На проверке', AppColors.hit),
  approved('Подключена', AppColors.fresh),
  rejected('Отклонена', AppColors.lowStock),
  suspended('Приостановлена', AppColors.lowStock);

  const B2BStatus(this.label, this.color);
  final String label;
  final Color color;

  static B2BStatus parse(String s) =>
      values.firstWhere((v) => v.name == s, orElse: () => pending);
}

@immutable
class B2BMember {
  const B2BMember({
    required this.id,
    required this.name,
    this.phone,
    this.email,
  });
  final int id;
  final String name;
  final String? phone;
  final String? email;

  factory B2BMember.fromJson(Map<String, dynamic> j) => B2BMember(
    id: j['id'] as int,
    name: j['full_name'] as String,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
  );
}

@immutable
class B2BCompany {
  const B2BCompany({
    required this.id,
    required this.legalName,
    required this.taxId,
    required this.status,
    required this.createdAt,
    this.note,
    this.members = const [],
  });

  final int id;
  final String legalName;
  final String taxId;
  final B2BStatus status;
  final DateTime createdAt;
  final String? note;
  final List<B2BMember> members;

  factory B2BCompany.fromJson(Map<String, dynamic> j) => B2BCompany(
    id: j['id'] as int,
    legalName: j['legal_name'] as String,
    taxId: j['tax_id'] as String,
    status: B2BStatus.parse(j['status'] as String),
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    note: j['note'] as String?,
    members: [
      for (final m in (j['members'] as List).cast<Map<String, dynamic>>())
        B2BMember.fromJson(m),
    ],
  );

  B2BCompany decided({required bool approve, String? note}) => B2BCompany(
    id: id,
    legalName: legalName,
    taxId: taxId,
    status: approve ? B2BStatus.approved : B2BStatus.rejected,
    createdAt: createdAt,
    note: note,
    members: members,
  );
}

/// Заказ глазами курьера: без фамилии и цен товаров; телефон — только когда открыт.
@immutable
class CourierOrder {
  const CourierOrder({
    required this.id,
    required this.number,
    required this.customerName,
    required this.address,
    required this.itemsCount,
    required this.total,
    required this.phoneMasked,
    required this.mine,
    this.note,
    this.cashToCollect,
    this.phone,
    this.phoneRevealReason,
    this.distanceKm,
    this.destLat,
    this.destLng,
    this.delivered = false,
  });

  final int id;
  final String number;
  final String customerName;
  final String address;
  final String? note;
  final int itemsCount;
  final double total;
  final double? cashToCollect;
  final String? phone;
  final String phoneMasked;
  final String? phoneRevealReason;
  final double? distanceKm;
  final double? destLat;
  final double? destLng;
  final bool mine;
  final bool delivered;

  CourierOrder copyWith({
    String? phone,
    String? phoneRevealReason,
    double? distanceKm,
    bool? mine,
    bool? delivered,
  }) => CourierOrder(
    id: id,
    number: number,
    customerName: customerName,
    address: address,
    note: note,
    itemsCount: itemsCount,
    total: total,
    cashToCollect: cashToCollect,
    phone: phone ?? this.phone,
    phoneMasked: phoneMasked,
    phoneRevealReason: phoneRevealReason ?? this.phoneRevealReason,
    distanceKm: distanceKm ?? this.distanceKm,
    destLat: destLat,
    destLng: destLng,
    mine: mine ?? this.mine,
    delivered: delivered ?? this.delivered,
  );

  factory CourierOrder.fromJson(Map<String, dynamic> j) => CourierOrder(
    id: j['id'] as int,
    number: j['number'] as String,
    customerName: j['customer_name'] as String,
    address: j['address'] as String,
    note: j['note'] as String?,
    itemsCount: j['items_count'] as int,
    total: _d(j['total']),
    cashToCollect: j['cash_to_collect'] == null
        ? null
        : _d(j['cash_to_collect']),
    phone: j['phone'] as String?,
    phoneMasked: j['phone_masked'] as String,
    phoneRevealReason: j['phone_reveal_reason'] as String?,
    distanceKm: (j['distance_km'] as num?)?.toDouble(),
    destLat: (j['dest_lat'] as num?)?.toDouble(),
    destLng: (j['dest_lng'] as num?)?.toDouble(),
    mine: j['mine'] as bool,
    delivered: j['status'] == 'delivered',
  );
}

@immutable
class StorySlideData {
  const StorySlideData({
    required this.imageUrl,
    required this.headline,
    this.caption,
    this.ctaLabel,
    this.ctaUrl,
  });
  final String imageUrl;
  final String headline;
  final String? caption;
  final String? ctaLabel;
  final String? ctaUrl;

  Map<String, dynamic> toJson() => {
    'image_url': imageUrl,
    'headline': headline,
    'caption': caption,
    'cta_label': ctaLabel,
    'cta_url': ctaUrl,
  };

  factory StorySlideData.fromJson(Map<String, dynamic> j) => StorySlideData(
    imageUrl: j['image_url'] as String,
    headline: j['headline'] as String,
    caption: j['caption'] as String?,
    ctaLabel: j['cta_label'] as String?,
    ctaUrl: j['cta_url'] as String?,
  );
}

@immutable
class AdminStory {
  const AdminStory({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.color,
    required this.slides,
    this.isActive = true,
    this.startsAt,
    this.endsAt,
  });
  final int id; // 0 — ещё не сохранена
  final String title;
  final String coverUrl;
  final Color color;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final List<StorySlideData> slides;

  bool get isLive {
    final now = DateTime.now();
    return isActive &&
        (startsAt == null || !startsAt!.isAfter(now)) &&
        (endsAt == null || endsAt!.isAfter(now));
  }

  AdminStory copyWith({int? id, bool? isActive}) => AdminStory(
    id: id ?? this.id,
    title: title,
    coverUrl: coverUrl,
    color: color,
    slides: slides,
    isActive: isActive ?? this.isActive,
    startsAt: startsAt,
    endsAt: endsAt,
  );

  static String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Map<String, dynamic> toJson() => {
    'title': title,
    'cover_url': coverUrl,
    'color_hex': hex(color),
    'is_active': isActive,
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'slides': [for (final s in slides) s.toJson()],
  };

  factory AdminStory.fromJson(Map<String, dynamic> j) => AdminStory(
    id: j['id'] as int,
    title: j['title'] as String,
    coverUrl: j['cover_url'] as String,
    color: Color(
      int.parse((j['color_hex'] as String).substring(1), radix: 16) |
          0xFF000000,
    ),
    isActive: j['is_active'] as bool? ?? true,
    startsAt: DateTime.tryParse(j['starts_at'] as String? ?? '')?.toLocal(),
    endsAt: DateTime.tryParse(j['ends_at'] as String? ?? '')?.toLocal(),
    slides: [
      for (final s in (j['slides'] as List).cast<Map<String, dynamic>>())
        StorySlideData.fromJson(s),
    ],
  );
}

double _money(Object? v) => v is num ? v.toDouble() : double.parse(v as String);

/// Контакты, условия доставки и реквизиты — всё, что видно покупателю на сайте.
@immutable
class ShopSettings {
  const ShopSettings({
    this.phone = '+7 (985) 394-72-62',
    this.email = '',
    this.minOrder = 2500,
    this.courierFee = 199,
    this.freeFrom = 5000,
    this.expressEnabled = true,
    this.expressFee = 349,
    this.expressHours = 2,
    this.pickupEnabled = true,
    this.legalName = '',
    this.legalInn = '',
    this.legalOgrn = '',
    this.legalAddress = '',
  });

  final String phone;
  final String email;
  final double minOrder;
  final double courierFee;
  final double? freeFrom; // null — курьер всегда платный, 0 — всегда бесплатный
  final bool expressEnabled;
  final double expressFee;
  final int expressHours;
  final bool pickupEnabled;
  final String legalName;
  final String legalInn;
  final String legalOgrn;
  final String legalAddress;

  factory ShopSettings.fromJson(Map<String, dynamic> j) => ShopSettings(
    phone: j['contact_phone'] as String,
    email: j['contact_email'] as String? ?? '',
    minOrder: _money(j['delivery_min_order']),
    courierFee: _money(j['courier_fee']),
    freeFrom: j['free_delivery_from'] == null
        ? null
        : _money(j['free_delivery_from']),
    expressEnabled: j['express_enabled'] as bool,
    expressFee: _money(j['express_fee']),
    expressHours: j['express_hours'] as int,
    pickupEnabled: j['pickup_enabled'] as bool,
    legalName: j['legal_name'] as String? ?? '',
    legalInn: j['legal_inn'] as String? ?? '',
    legalOgrn: j['legal_ogrn'] as String? ?? '',
    legalAddress: j['legal_address'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'contact_phone': phone,
    'contact_email': email,
    'delivery_min_order': minOrder.toStringAsFixed(2),
    'courier_fee': courierFee.toStringAsFixed(2),
    'free_delivery_from': freeFrom?.toStringAsFixed(2),
    'express_enabled': expressEnabled,
    'express_fee': expressFee.toStringAsFixed(2),
    'express_hours': expressHours,
    'pickup_enabled': pickupEnabled,
    'legal_name': legalName,
    'legal_inn': legalInn,
    'legal_ogrn': legalOgrn,
    'legal_address': legalAddress,
  };
}

@immutable
class ReferralSettings {
  const ReferralSettings({
    this.enabled = true,
    this.friendAmount = 300,
    this.inviterAmount = 300,
    this.minOrder = 2500,
  });
  final bool enabled;
  final double friendAmount;
  final double inviterAmount;
  final double minOrder;

  factory ReferralSettings.fromJson(Map<String, dynamic> j) => ReferralSettings(
    enabled: j['referral_enabled'] as bool,
    friendAmount: _money(j['referral_friend_amount']),
    inviterAmount: _money(j['referral_inviter_amount']),
    minOrder: _money(j['referral_min_order']),
  );

  Map<String, dynamic> toJson() => {
    'referral_enabled': enabled,
    'referral_friend_amount': friendAmount.toStringAsFixed(2),
    'referral_inviter_amount': inviterAmount.toStringAsFixed(2),
    'referral_min_order': minOrder.toStringAsFixed(2),
  };
}

enum BannerTheme {
  green('Зелёный', Color(0xFF0B5D3B), Colors.white),
  orange('Оранжевый', Color(0xFFFB8C00), Color(0xFF1F2A1F)),
  cream('Светлый', Color(0xFFF1EDE3), Color(0xFF17291F));

  const BannerTheme(this.label, this.background, this.foreground);
  final String label;
  final Color background;
  final Color foreground;
}

enum ButtonColor {
  orange('Оранжевая', Color(0xFFFFA726), Color(0xFF1F2A1F)),
  green('Зелёная', Color(0xFF0B5D3B), Colors.white),
  white('Белая', Colors.white, Color(0xFF17291F)),
  dark('Тёмная', Color(0xFF17291F), Colors.white);

  const ButtonColor(this.label, this.background, this.foreground);
  final String label;
  final Color background;
  final Color foreground;
}

/// Баннер-слайд на главной сайта.
@immutable
class AdminBanner {
  const AdminBanner({
    this.id = 0,
    required this.title,
    this.text = '',
    this.imageUrl,
    this.buttonLabel,
    this.linkUrl,
    this.theme = BannerTheme.green,
    this.buttonColor = ButtonColor.orange,
    this.isActive = true,
    this.startsAt,
    this.endsAt,
  });

  final int id;
  final String title;
  final String text;
  final String? imageUrl;
  final String? buttonLabel;
  final String? linkUrl;
  final BannerTheme theme;
  final ButtonColor buttonColor;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;

  bool get visibleNow {
    final now = DateTime.now();
    return isActive &&
        (startsAt == null || !startsAt!.isAfter(now)) &&
        (endsAt == null || endsAt!.isAfter(now));
  }

  factory AdminBanner.fromJson(Map<String, dynamic> j) => AdminBanner(
    id: j['id'] as int,
    title: j['title'] as String,
    text: j['text'] as String? ?? '',
    imageUrl: j['image_url'] as String?,
    buttonLabel: j['button_label'] as String?,
    linkUrl: j['link_url'] as String?,
    theme: BannerTheme.values.firstWhere(
      (t) => t.name == j['theme'],
      orElse: () => BannerTheme.green,
    ),
    buttonColor: ButtonColor.values.firstWhere(
      (c) => c.name == j['button_color'],
      orElse: () => ButtonColor.orange,
    ),
    isActive: j['is_active'] as bool? ?? true,
    startsAt: j['starts_at'] == null
        ? null
        : DateTime.parse(j['starts_at'] as String).toLocal(),
    endsAt: j['ends_at'] == null
        ? null
        : DateTime.parse(j['ends_at'] as String).toLocal(),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'text': text,
    'image_url': imageUrl,
    'button_label': buttonLabel,
    'link_url': linkUrl,
    'theme': theme.name,
    'button_color': buttonColor.name,
    'is_active': isActive,
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
  };

  AdminBanner copyWith({int? id, bool? isActive}) => AdminBanner(
    id: id ?? this.id,
    title: title,
    text: text,
    imageUrl: imageUrl,
    buttonLabel: buttonLabel,
    linkUrl: linkUrl,
    theme: theme,
    buttonColor: buttonColor,
    isActive: isActive ?? this.isActive,
    startsAt: startsAt,
    endsAt: endsAt,
  );
}

/// Диалог покупателя с поддержкой — строка во «Входящих».
@immutable
class SupportThread {
  const SupportThread({
    required this.userId,
    required this.name,
    required this.lastText,
    required this.lastAt,
    this.phone,
    this.email,
    this.lastFromStaff = false,
    this.unread = 0,
  });

  final int userId;
  final String name;
  final String? phone;
  final String? email;
  final String lastText;
  final DateTime lastAt;
  final bool lastFromStaff;
  final int unread;

  factory SupportThread.fromJson(Map<String, dynamic> j) => SupportThread(
    userId: j['user_id'] as int,
    name: j['name'] as String,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    lastText: j['last_text'] as String,
    lastAt: DateTime.parse(j['last_at'] as String).toLocal(),
    lastFromStaff: j['last_from_staff'] as bool? ?? false,
    unread: j['unread'] as int? ?? 0,
  );

  SupportThread read() => SupportThread(
    userId: userId,
    name: name,
    phone: phone,
    email: email,
    lastText: lastText,
    lastAt: lastAt,
    lastFromStaff: lastFromStaff,
  );
}

@immutable
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.text,
    required this.fromStaff,
    required this.author,
    required this.createdAt,
  });
  final int id;
  final String text;
  final bool fromStaff;
  final String author;
  final DateTime createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
    id: j['id'] as int,
    text: j['text'] as String,
    fromStaff: j['from_staff'] as bool,
    author: j['author'] as String,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );
}
