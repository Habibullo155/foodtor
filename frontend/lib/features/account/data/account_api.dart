import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/password_policy.dart';
import '../../catalog/data/demo_catalog.dart';
import '../account.dart';

double _d(Object? v) => v == null ? 0 : double.parse(v.toString());

/// Относительные пути (/media/…) → абсолютные: API может жить на другом домене (dev).
String? absUrl(String? url) {
  if (url == null || url.startsWith('http') || url.startsWith('assets/')) {
    return url;
  }
  return '${apiBaseUrl()}$url';
}

@immutable
class Me {
  const Me({
    required this.id,
    this.email,
    required this.fullName,
    required this.account,
    this.phone,
    this.avatarUrl,
  });

  final int id;
  final String? email; // null — вошёл по номеру телефона (SMS)
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final Account account;

  String get login => email ?? phone ?? '';

  String get initials => fullName
      .split(' ')
      .where((p) => p.isNotEmpty)
      .take(2)
      .map((p) => p[0])
      .join();

  Me copyWith({
    String? fullName,
    String? phone,
    String? Function()? avatarUrl,
  }) => Me(
    id: id,
    email: email,
    fullName: fullName ?? this.fullName,
    phone: phone ?? this.phone,
    avatarUrl: avatarUrl != null ? avatarUrl() : this.avatarUrl,
    account: account,
  );

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    id: j['id'] as int,
    email: j['email'] as String?,
    fullName: j['full_name'] as String,
    phone: j['phone'] as String?,
    avatarUrl: absUrl(j['avatar_url'] as String?),
    account: Account.fromJson(j),
  );
}

enum OrderState {
  newOrder('new', 'Принят'),
  picking('picking', 'Собираем'),
  shipped('shipped', 'В пути'),
  delivered('delivered', 'Доставлен'),
  cancelled('cancelled', 'Отменён');

  const OrderState(this.code, this.label);
  final String code;
  final String label;
  static OrderState parse(String c) =>
      values.firstWhere((s) => s.code == c, orElse: () => newOrder);
  bool get isClosed => this == delivered || this == cancelled;
}

@immutable
class OrderLineView {
  const OrderLineView({
    required this.name,
    required this.qty,
    required this.price,
    this.productId,
    this.imageUrl,
    this.unit,
  });
  final int? productId;
  final String name;
  final int qty;
  final double price; // за единицу
  final String? imageUrl;
  final String? unit;
  double get total => price * qty;
}

@immutable
class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.number,
    required this.state,
    required this.paymentStatus,
    required this.total,
    required this.createdAt,
    required this.lines,
    this.deliveryFee = 0,
    this.delivery = 'courier',
    this.paymentMethod = 'cash',
    this.payUrl,
  });

  final int id;
  final String number;
  final OrderState state;
  final String
  paymentStatus; // not_required | pending | paid | failed | refunded
  final double total;
  final double deliveryFee;
  final DateTime createdAt;
  final List<OrderLineView> lines;
  final String delivery; // express | courier | pickup
  final String paymentMethod; // cash | card_online
  final String? payUrl;

  int get itemsCount => lines.fold(0, (a, l) => a + l.qty);
  List<String> get preview => [for (final l in lines.take(4)) ?l.imageUrl];
  bool get awaitingPayment =>
      paymentMethod == 'card_online' &&
      (paymentStatus == 'pending' || paymentStatus == 'failed');
  String get paymentLabel => switch ((paymentMethod, paymentStatus)) {
    (_, 'paid') => 'Оплачен картой',
    ('card_online', 'refunded') => 'Деньги возвращены',
    ('card_online', _) => 'Ожидает оплаты',
    _ => 'Оплата при получении',
  };
  String get deliveryLabel => switch (delivery) {
    'express' => 'Экспресс за 2 часа',
    'pickup' => 'Самовывоз',
    _ => 'Курьер',
  };

  factory CustomerOrder.fromJson(Map<String, dynamic> j) => CustomerOrder(
    id: j['id'] as int,
    number: j['number'] as String,
    state: OrderState.parse(j['status'] as String),
    paymentStatus: j['payment_status'] as String,
    paymentMethod: j['payment_method'] as String? ?? 'cash',
    delivery: j['delivery'] as String? ?? 'courier',
    total: _d(j['total']),
    deliveryFee: _d(j['delivery_fee']),
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    payUrl: j['pay_url'] as String?,
    lines: [
      for (final i in (j['items'] as List).cast<Map<String, dynamic>>())
        OrderLineView(
          productId: i['product_id'] as int?,
          name: i['name'] as String,
          qty: i['quantity'] as int,
          price: _d(i['unit_price']),
          imageUrl: absUrl(i['image_url'] as String?),
          unit: i['unit'] as String?,
        ),
    ],
  );
}

@immutable
class Purchase {
  const Purchase({
    required this.productId,
    required this.name,
    required this.timesBought,
    required this.lastBoughtAt,
    this.imageUrl,
    this.unit,
    this.price,
    this.inStock = true,
  });

  final int productId;
  final String name;
  final String? imageUrl;
  final String? unit;
  final int timesBought;
  final DateTime lastBoughtAt;
  final double? price; // null — снят с продажи
  final bool inStock;

  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
    productId: j['product_id'] as int,
    name: j['name'] as String,
    imageUrl: absUrl(j['image_url'] as String?),
    unit: j['unit'] as String?,
    timesBought: j['times_bought'] as int,
    lastBoughtAt: DateTime.parse(j['last_bought_at'] as String).toLocal(),
    price: j['price'] == null ? null : _d(j['price']),
    inStock: j['in_stock'] as bool? ?? false,
  );
}

@immutable
class Address {
  const Address({
    required this.id,
    required this.address,
    this.label = 'Дом',
    this.apartment,
    this.entrance,
    this.floor,
    this.intercom,
    this.courierNote,
    this.isDefault = false,
    this.lat,
    this.lng,
  });

  final int id; // 0 — ещё не сохранён
  final double?
  lat; // точка с карты (если выбирали) — по ней проверяется зона и едет курьер
  final double? lng;
  final String label;
  final String address;
  final String? apartment;
  final String? entrance;
  final String? floor;
  final String? intercom;
  final String? courierNote;
  final bool isDefault;

  String get oneLine => [
    address,
    if (apartment?.isNotEmpty ?? false) 'кв. $apartment',
    if (entrance?.isNotEmpty ?? false) 'подъезд $entrance',
    if (floor?.isNotEmpty ?? false) 'этаж $floor',
    if (intercom?.isNotEmpty ?? false) 'домофон $intercom',
  ].join(', ');

  Address withDefault(bool v) => Address(
    id: id,
    address: address,
    label: label,
    apartment: apartment,
    entrance: entrance,
    floor: floor,
    intercom: intercom,
    courierNote: courierNote,
    isDefault: v,
    lat: lat,
    lng: lng,
  );

  Address withId(int newId) => Address(
    id: newId,
    address: address,
    label: label,
    apartment: apartment,
    entrance: entrance,
    floor: floor,
    intercom: intercom,
    courierNote: courierNote,
    isDefault: isDefault,
    lat: lat,
    lng: lng,
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'address': address,
    'apartment': apartment,
    'entrance': entrance,
    'floor': floor,
    'intercom': intercom,
    'courier_note': courierNote,
    'is_default': isDefault,
    'lat': lat,
    'lng': lng,
  };

  factory Address.fromJson(Map<String, dynamic> j) => Address(
    id: j['id'] as int,
    label: j['label'] as String,
    address: j['address'] as String,
    apartment: j['apartment'] as String?,
    entrance: j['entrance'] as String?,
    floor: j['floor'] as String?,
    intercom: j['intercom'] as String?,
    courierNote: j['courier_note'] as String?,
    isDefault: j['is_default'] as bool? ?? false,
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
  );
}

@immutable
class OrderMessage {
  const OrderMessage({
    required this.text,
    required this.fromStaff,
    required this.author,
    required this.createdAt,
  });
  final String text;
  final bool fromStaff;
  final String author;
  final DateTime createdAt;

  factory OrderMessage.fromJson(Map<String, dynamic> j) => OrderMessage(
    text: j['text'] as String,
    fromStaff: j['from_staff'] as bool,
    author: j['author'] as String,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );
}

/// Курьер по заказу «в пути»: имя, насколько близко, открыт ли ему телефон.
class CourierInfo {
  const CourierInfo({
    required this.assigned,
    this.name,
    this.distanceKm,
    this.phoneOpened = false,
    this.phoneRevealReason,
  });
  final bool assigned;
  final String? name;
  final double? distanceKm;
  final bool phoneOpened;
  final String? phoneRevealReason;

  factory CourierInfo.fromJson(Map<String, dynamic> j) => CourierInfo(
    assigned: j['assigned'] as bool,
    name: j['courier_name'] as String?,
    distanceKm: (j['distance_km'] as num?)?.toDouble(),
    phoneOpened: j['phone_opened'] as bool? ?? false,
    phoneRevealReason: j['phone_reveal_reason'] as String?,
  );
}

enum CodeChannel {
  sms('phone'),
  email('email');

  const CodeChannel(this.path);
  final String path; // /auth/{path}/request
}

class CodeSent {
  const CodeSent(this.target, this.resendIn, [this.devCode]);
  final String target;
  final int resendIn;
  final String? devCode;
}

class PhoneVerifyResult {
  const PhoneVerifyResult({this.signupToken});
  final String? signupToken;
  bool get needsName => signupToken != null;
}

abstract interface class AccountApi {
  Future<Me> me();
  Future<void> login(String email, String password);
  Future<CodeSent> requestCode(CodeChannel channel, String target);
  Future<PhoneVerifyResult> verifyCode(
    CodeChannel channel,
    String target,
    String code,
  );
  Future<void> completeSignup(
    CodeChannel channel,
    String signupToken,
    String name,
  );
  Future<void> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  });
  Future<Me> updateProfile(Me current, {required String name, String? phone});
  Future<void> changePassword(String current, String next);
  Future<void> logoutAll();
  Future<String?> uploadAvatar(List<int> bytes, String filename);
  Future<void> deleteAvatar();
  Future<Map<String, dynamic>> loyalty();
  Future<List<CustomerOrder>> orders();
  Future<List<Purchase>> purchases();
  Future<List<Address>> addresses();
  Future<Address> saveAddress(Address a);
  Future<void> deleteAddress(int id);
  Future<List<OrderMessage>> comments(int orderId);
  Future<List<OrderMessage>> addComment(int orderId, String text);
  Future<String> payAgain(int orderId);
  Future<CourierInfo> courier(int orderId);
  Future<List<OrderMessage>> courierChat(int orderId);
  Future<List<OrderMessage>> courierSay(int orderId, String text);
}

final accountApiProvider = Provider<AccountApi>(
  (ref) => AppConfig.isDemo ? DemoAccountApi() : HttpAccountApi(ref),
);

class HttpAccountApi implements AccountApi {
  HttpAccountApi(this._ref);
  final Ref _ref;
  Dio get _dio => _ref.read(dioProvider);

  Future<T> _wrap<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  List<Map<String, dynamic>> _list(Response<dynamic> r) =>
      (r.data as List).cast<Map<String, dynamic>>();

  @override
  Future<Me> me() => _wrap(
    () async => Me.fromJson(
      (await _dio.get<Map<String, dynamic>>('/api/v1/auth/me')).data!,
    ),
  );

  @override
  Future<void> login(String email, String password) =>
      loginWithPassword(_ref, email, password);

  @override
  Future<void> changePassword(String current, String next) =>
      changePasswordSession(_ref, current, next);

  Future<void> _saveTokens(Map<String, dynamic> j) => _ref
      .read(tokenStoreProvider)
      .save(j['access_token'] as String, j['refresh_token'] as String);

  @override
  Future<CodeSent> requestCode(CodeChannel channel, String target) =>
      _wrap(() async {
        final j = (await _dio.post<Map<String, dynamic>>(
          '/api/v1/auth/${channel.path}/request',
          data: {channel.path: target.trim()},
        )).data!;
        return CodeSent(
          j['target'] as String,
          j['resend_in'] as int,
          j['dev_code'] as String?,
        );
      });

  @override
  Future<PhoneVerifyResult> verifyCode(
    CodeChannel channel,
    String target,
    String code,
  ) => _wrap(() async {
    final j = (await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/${channel.path}/verify',
      data: {channel.path: target, 'code': code},
    )).data!;
    if (j['status'] == 'ok') {
      await _saveTokens(j);
      return const PhoneVerifyResult();
    }
    return PhoneVerifyResult(signupToken: j['signup_token'] as String);
  });

  @override
  Future<void> completeSignup(
    CodeChannel channel,
    String signupToken,
    String name,
  ) => _wrap(() async {
    final j = (await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/${channel.path}/complete',
      data: {'signup_token': signupToken, 'full_name': name.trim()},
    )).data!;
    await _saveTokens(j);
  });

  @override
  Future<void> logoutAll() => logoutEverywhere(_ref);

  @override
  Future<void> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) => _wrap(() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/register',
      data: {
        'email': email.trim(),
        'password': password,
        'full_name': name.trim(),
        'phone': ?phone,
      },
    );
    await _ref
        .read(tokenStoreProvider)
        .save(
          r.data!['access_token'] as String,
          r.data!['refresh_token'] as String,
        );
  });

  @override
  Future<Me> updateProfile(Me current, {required String name, String? phone}) =>
      _wrap(() async {
        final j = (await _dio.patch<Map<String, dynamic>>(
          '/api/v1/me/profile',
          data: {'full_name': name, 'phone': ?phone},
        )).data!;
        return current.copyWith(
          fullName: j['full_name'] as String,
          phone: j['phone'] as String?,
        );
      });

  @override
  Future<String?> uploadAvatar(List<int> bytes, String filename) =>
      _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/api/v1/me/avatar',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes(bytes, filename: filename),
          }),
        );
        return absUrl(r.data!['avatar_url'] as String?);
      });

  @override
  Future<void> deleteAvatar() =>
      _wrap(() => _dio.delete<dynamic>('/api/v1/me/avatar'));

  @override
  Future<Map<String, dynamic>> loyalty() => _wrap(
    () async =>
        (await _dio.get<Map<String, dynamic>>('/api/v1/me/loyalty')).data!,
  );

  @override
  Future<List<CustomerOrder>> orders() => _wrap(
    () async => [
      for (final o in _list(await _dio.get<dynamic>('/api/v1/me/orders')))
        CustomerOrder.fromJson(o),
    ],
  );

  @override
  Future<List<Purchase>> purchases() => _wrap(
    () async => [
      for (final p in _list(await _dio.get<dynamic>('/api/v1/me/purchases')))
        Purchase.fromJson(p),
    ],
  );

  @override
  Future<List<Address>> addresses() => _wrap(
    () async => [
      for (final a in _list(await _dio.get<dynamic>('/api/v1/me/addresses')))
        Address.fromJson(a),
    ],
  );

  @override
  Future<Address> saveAddress(Address a) => _wrap(() async {
    final r = a.id == 0
        ? await _dio.post<Map<String, dynamic>>(
            '/api/v1/me/addresses',
            data: a.toJson(),
          )
        : await _dio.put<Map<String, dynamic>>(
            '/api/v1/me/addresses/${a.id}',
            data: a.toJson(),
          );
    return Address.fromJson(r.data!);
  });

  @override
  Future<void> deleteAddress(int id) =>
      _wrap(() => _dio.delete<dynamic>('/api/v1/me/addresses/$id'));

  @override
  Future<List<OrderMessage>> comments(int orderId) => _wrap(
    () async => [
      for (final c in _list(
        await _dio.get<dynamic>('/api/v1/me/orders/$orderId/comments'),
      ))
        OrderMessage.fromJson(c),
    ],
  );

  @override
  Future<List<OrderMessage>> addComment(int orderId, String text) => _wrap(
    () async => [
      for (final c in _list(
        await _dio.post<dynamic>(
          '/api/v1/me/orders/$orderId/comments',
          data: {'text': text},
        ),
      ))
        OrderMessage.fromJson(c),
    ],
  );

  @override
  Future<String> payAgain(int orderId) => _wrap(
    () async =>
        (await _dio.post<Map<String, dynamic>>(
              '/api/v1/me/orders/$orderId/pay',
            )).data!['pay_url']
            as String,
  );

  @override
  Future<CourierInfo> courier(int orderId) => _wrap(
    () async => CourierInfo.fromJson(
      (await _dio.get<Map<String, dynamic>>(
        '/api/v1/me/orders/$orderId/courier',
      )).data!,
    ),
  );

  @override
  Future<List<OrderMessage>> courierChat(int orderId) => _wrap(
    () async => [
      for (final c in (await _dio.get<List<dynamic>>(
        '/api/v1/me/orders/$orderId/courier-chat',
      )).data!.cast<Map<String, dynamic>>())
        OrderMessage.fromJson(c),
    ],
  );

  @override
  Future<List<OrderMessage>> courierSay(int orderId, String text) => _wrap(
    () async => [
      for (final c in (await _dio.post<List<dynamic>>(
        '/api/v1/me/orders/$orderId/courier-chat',
        data: {'text': text},
      )).data!.cast<Map<String, dynamic>>())
        OrderMessage.fromJson(c),
    ],
  );
}

/// Демо-покупательница: заказы, история, адреса и переписка — в памяти, чтобы показать кабинет без сервера.
class DemoAccountApi implements AccountApi {
  static final _now = DateTime.now();
  Me _me = _maria;

  late final List<Address> _addresses = [
    const Address(
      id: 1,
      label: 'Дом',
      address: 'Москва, ул. Тверская, 12',
      apartment: '45',
      entrance: '2',
      floor: '7',
      intercom: '45К',
      courierNote: 'Позвонить за 10 минут',
      isDefault: true,
    ),
    const Address(
      id: 2,
      label: 'Работа',
      address: 'Москва, Ленинградский пр-т, 39с1',
      floor: '3',
      courierNote: 'Ресепшен, офис 301',
    ),
  ];

  final _otherBooks = <int, List<Address>>{};
  List<Address> get _book =>
      _isMaria ? _addresses : _otherBooks.putIfAbsent(_me.id, () => []);

  static OrderLineView _line(int itemId, int qty) {
    final i = demoItems.firstWhere((x) => x.id == itemId);
    return OrderLineView(
      productId: i.id,
      name: i.name,
      qty: qty,
      price: i.price,
      imageUrl: ingredientImage(i.image),
      unit: i.unit,
    );
  }

  static CustomerOrder _order(
    int id,
    String number,
    OrderState s,
    int daysAgo,
    List<OrderLineView> lines, {
    String payment = 'cash',
    String paymentStatus = 'not_required',
    String delivery = 'courier',
  }) {
    final goods = lines.fold(0.0, (a, l) => a + l.total);
    final fee = delivery == 'express' ? 149.0 : (goods >= 1500 ? 0.0 : 199.0);
    return CustomerOrder(
      id: id,
      number: number,
      state: s,
      paymentStatus: paymentStatus,
      paymentMethod: payment,
      delivery: delivery,
      total: goods + fee,
      deliveryFee: fee,
      createdAt: _now.subtract(Duration(days: daysAgo, hours: 2)),
      lines: lines,
    );
  }

  late final List<CustomerOrder> _orders = [
    _order(
      105,
      '261019-7KQ2',
      OrderState.shipped,
      0,
      [_line(29, 2), _line(30, 1), _line(71, 1)],
      payment: 'card_online',
      paymentStatus: 'paid',
      delivery: 'express',
    ),
    _order(104, '261012-3FD8', OrderState.delivered, 7, [
      _line(1, 2),
      _line(2, 1),
      _line(35, 1),
      _line(54, 1),
      _line(57, 1),
    ]),
    _order(
      103,
      '261005-9AB1',
      OrderState.delivered,
      14,
      [_line(63, 1), _line(69, 1), _line(18, 2)],
      payment: 'card_online',
      paymentStatus: 'paid',
    ),
    _order(102, '260928-1CC7', OrderState.cancelled, 21, [
      _line(10, 1),
      _line(13, 2),
    ]),
    _order(101, '260921-5EE3', OrderState.delivered, 28, [
      _line(1, 1),
      _line(44, 2),
      _line(17, 3),
      _line(36, 1),
    ]),
  ];

  late final Map<int, List<OrderMessage>> _comments = {
    105: [
      OrderMessage(
        text: 'Пожалуйста, оставьте пакет у двери — я на созвоне',
        fromStaff: false,
        author: _me.fullName,
        createdAt: _now.subtract(const Duration(minutes: 40)),
      ),
      OrderMessage(
        text: 'Конечно! Курьер позвонит в домофон и оставит у двери.',
        fromStaff: true,
        author: 'Магазин',
        createdAt: _now.subtract(const Duration(minutes: 32)),
      ),
    ],
  };

  Future<T> _later<T>(T v) =>
      Future.value(v); // демо: без искусственной задержки (и висящих таймеров)

  static const _maria = Me(
    id: 1,
    email: 'maria@example.ru',
    fullName: 'Мария Кузнецова',
    phone: '+7 916 123-45-67',
    account: Account(type: AccountType.b2c),
  );

  /// Аккаунты, зарегистрированные в этой вкладке (демо без сервера): email → пароль.
  final _accounts = <String, ({String password, Me me})>{};
  final _fails = <String, int>{};
  bool get _isMaria => _me.id == 1;

  /// Кнопка «Войти как демо-покупатель» — без пароля, только в демо.
  void useDemoCustomer() => _me = _maria;

  @override
  Future<Me> me() => _later(_me);

  @override
  Future<void> login(String email, String password) async {
    final key = email.trim().toLowerCase();
    // Как на сервере: 5 ошибок подряд — вход в этот email закрыт (в демо — до перезагрузки)
    if ((_fails[key] ?? 0) >= 5) {
      throw ApiException(
        'Слишком много неудачных попыток. Вход временно закрыт — попробуйте через 15 мин.',
        status: 429,
      );
    }
    final acc = _accounts[key];
    if (acc == null || acc.password != password) {
      _fails[key] = (_fails[key] ?? 0) + 1;
      throw ApiException('Неверный email или пароль', status: 401);
    }
    _fails.remove(key);
    _me = acc.me;
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key) || key == _maria.email) {
      throw ApiException('Этот email уже зарегистрирован', status: 409);
    }
    if (passwordProblem(password, email: key) case final p?) {
      throw ApiException(p, status: 422);
    }
    final me = Me(
      id: 100 + _accounts.length,
      email: key,
      fullName: name.trim(),
      phone: phone,
      account: const Account(type: AccountType.b2c),
    );
    _accounts[key] = (password: password, me: me);
    _me = me;
  }

  @override
  Future<void> changePassword(String current, String next) async {
    final acc = _accounts[_me.email ?? ''];
    if (acc != null && acc.password != current) {
      throw ApiException('Текущий пароль указан неверно', status: 400);
    }
    if (passwordProblem(next, email: _me.email) case final p?) {
      throw ApiException(p, status: 422);
    }
    if (acc != null) _accounts[_me.email ?? ''] = (password: next, me: acc.me);
  }

  @override
  Future<void> logoutAll() async {}

  // Вход по SMS (демо): код показывается на экране, у Марии номер +79161234567
  final _codes =
      <String, ({String code, int fails})>{}; // «sms:+7…» / «email:…»
  final _phoneUsers = <String, Me>{'+79161234567': _maria};

  static String? _normalize(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 10) d = '7$d';
    if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
    return d.length == 11 && d.startsWith('79') ? '+$d' : null;
  }

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String _target(CodeChannel channel, String raw) {
    if (channel == CodeChannel.email) {
      final e = raw.trim().toLowerCase();
      if (!_emailRe.hasMatch(e)) {
        throw ApiException('Проверьте email', status: 422);
      }
      return e;
    }
    final p = _normalize(raw);
    if (p == null) {
      throw ApiException(
        'Укажите мобильный номер России: +7 9XX XXX-XX-XX',
        status: 422,
      );
    }
    return p;
  }

  Me? _knownBy(CodeChannel channel, String target) => channel == CodeChannel.sms
      ? _phoneUsers[target]
      : (target == _maria.email ? _maria : _accounts[target]?.me);

  @override
  Future<CodeSent> requestCode(CodeChannel channel, String target) async {
    final t = _target(channel, target);
    final code = (100000 + Random().nextInt(900000)).toString();
    _codes['${channel.name}:$t'] = (code: code, fails: 0);
    return CodeSent(t, 60, code);
  }

  @override
  Future<PhoneVerifyResult> verifyCode(
    CodeChannel channel,
    String target,
    String code,
  ) async {
    final t = _target(channel, target);
    final p = '${channel.name}:$t';
    final entry = _codes[p];
    if (entry == null) {
      throw ApiException('Код устарел — запросите новый', status: 400);
    }
    if (entry.fails >= 5) {
      throw ApiException(
        'Слишком много неверных попыток — запросите новый код',
        status: 429,
      );
    }
    if (entry.code != code.trim()) {
      final fails = entry.fails + 1;
      _codes[p] = (code: entry.code, fails: fails);
      throw ApiException(
        fails >= 5
            ? 'Неверный код — запросите новый'
            : 'Неверный код. Осталось попыток: ${5 - fails}',
        status: 400,
      );
    }
    _codes.remove(p);
    final existing = _knownBy(channel, t);
    if (existing != null) {
      _me = existing;
      return const PhoneVerifyResult();
    }
    return PhoneVerifyResult(signupToken: 'demo:$t');
  }

  @override
  Future<void> completeSignup(
    CodeChannel channel,
    String signupToken,
    String name,
  ) async {
    final t = signupToken.substring('demo:'.length);
    final me = Me(
      id: 200 + _phoneUsers.length + _accounts.length,
      fullName: name.trim(),
      phone: channel == CodeChannel.sms ? t : null,
      email: channel == CodeChannel.email ? t : null,
      account: const Account(type: AccountType.b2c),
    );
    if (channel == CodeChannel.sms) {
      _me = _phoneUsers[t] ??= me;
    } else {
      // вход по коду — пароль не нужен; случайный, чтобы по паролю без него не войти
      _me = (_accounts[t] ??= (
        password: '${Random().nextDouble()}',
        me: me,
      )).me;
    }
  }

  @override
  Future<Me> updateProfile(Me current, {required String name, String? phone}) =>
      _later(_me = _me.copyWith(fullName: name, phone: phone));

  @override
  Future<String?> uploadAvatar(List<int> bytes, String filename) async {
    // В демо фото не загружается на сервер — показываем одну из картинок витрины
    _me = _me.copyWith(avatarUrl: () => ingredientImage('Strawberries'));
    return _later(_me.avatarUrl);
  }

  @override
  Future<void> deleteAvatar() async =>
      _me = _me.copyWith(avatarUrl: () => null);

  @override
  Future<Map<String, dynamic>> loyalty() => _later({
    'current_tier': {
      'name': 'Silver',
      'color_hex': '#8E9AAF',
      'discount_type': 'percent',
      'discount_value': '3',
    },
    'next_tier': {
      'name': 'Gold',
      'color_hex': '#CA8A04',
      'discount_type': 'percent',
      'discount_value': '5',
    },
    'total_spent': '23500',
    'amount_to_next': '6500',
    'progress': 0.67,
  });

  @override
  Future<List<CustomerOrder>> orders() =>
      _later(_isMaria ? List.of(_orders) : <CustomerOrder>[]);

  @override
  Future<List<Purchase>> purchases() {
    final agg = <int, Purchase>{};
    for (final o in _orders.where(
      (o) => _isMaria && o.state == OrderState.delivered,
    )) {
      for (final l in o.lines) {
        final prev = agg[l.productId!];
        final item = demoItems.firstWhere((x) => x.id == l.productId);
        agg[l.productId!] = Purchase(
          productId: l.productId!,
          name: l.name,
          imageUrl: l.imageUrl,
          unit: l.unit,
          price: item.price,
          inStock: item.stock > 0,
          timesBought: (prev?.timesBought ?? 0) + 1,
          lastBoughtAt: prev == null || o.createdAt.isAfter(prev.lastBoughtAt)
              ? o.createdAt
              : prev.lastBoughtAt,
        );
      }
    }
    return _later(
      agg.values.toList()
        ..sort((a, b) => b.lastBoughtAt.compareTo(a.lastBoughtAt)),
    );
  }

  @override
  Future<List<Address>> addresses() => _later(List.of(_book));

  @override
  Future<Address> saveAddress(Address a) async {
    final saved = a.id == 0
        ? a.withId(_book.fold(0, (m, x) => x.id > m ? x.id : m) + 1)
        : a;
    final first = _book.isEmpty;
    if (saved.isDefault || first) {
      for (var i = 0; i < _book.length; i++) {
        _book[i] = _book[i].withDefault(false);
      }
    }
    final idx = _book.indexWhere((x) => x.id == saved.id);
    final value = first ? saved.withDefault(true) : saved;
    idx < 0 ? _book.add(value) : _book[idx] = value;
    return _later(value);
  }

  @override
  Future<void> deleteAddress(int id) async {
    final wasDefault = _book.firstWhere((a) => a.id == id).isDefault;
    _book.removeWhere((a) => a.id == id);
    if (wasDefault && _book.isNotEmpty) {
      _book[0] = _book[0].withDefault(true);
    }
  }

  @override
  Future<List<OrderMessage>> comments(int orderId) =>
      _later(List.of(_comments[orderId] ?? const []));

  @override
  Future<List<OrderMessage>> addComment(int orderId, String text) {
    final list = _comments.putIfAbsent(orderId, () => []);
    list.add(
      OrderMessage(
        text: text,
        fromStaff: false,
        author: _me.fullName,
        createdAt: DateTime.now(),
      ),
    );
    // Имитация ответа магазина через пару секунд
    Timer(const Duration(seconds: 2), () {
      list.add(
        OrderMessage(
          text: 'Спасибо, передали сборщику и курьеру!',
          fromStaff: true,
          author: 'Магазин',
          createdAt: DateTime.now(),
        ),
      );
    });
    return _later(List.of(list));
  }

  @override
  Future<String> payAgain(int orderId) =>
      _later('https://example.com/demo-payment');

  // Демо: заказ «в пути» везёт курьер Руслан, он в 2,4 км
  final _courierChat = <int, List<OrderMessage>>{
    105: [
      OrderMessage(
        text: 'Здравствуйте! Выехал к вам, буду минут через 15',
        fromStaff: true,
        author: 'Курьер Руслан',
        createdAt: _now.subtract(const Duration(minutes: 4)),
      ),
    ],
  };

  @override
  Future<CourierInfo> courier(int orderId) => _later(
    _isMaria && orderId == 105
        ? const CourierInfo(assigned: true, name: 'Руслан', distanceKm: 2.4)
        : const CourierInfo(assigned: false),
  );

  @override
  Future<List<OrderMessage>> courierChat(int orderId) =>
      _later(List.of(_courierChat[orderId] ?? const []));

  @override
  Future<List<OrderMessage>> courierSay(int orderId, String text) {
    final chat = _courierChat.putIfAbsent(orderId, () => []);
    chat.add(
      OrderMessage(
        text: text,
        fromStaff: false,
        author: _me.fullName.split(' ').first,
        createdAt: DateTime.now(),
      ),
    );
    chat.add(
      OrderMessage(
        text: 'Принял, спасибо!',
        fromStaff: true,
        author: 'Курьер Руслан',
        createdAt: DateTime.now(),
      ),
    );
    return _later(List.of(chat));
  }
}
