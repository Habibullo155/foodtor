import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/delivery/delivery_check.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../catalog/data/demo_catalog.dart';
import '../../account/data/account_api.dart' show OrderMessage;
import '../domain/admin_models.dart';

/// Источник данных админки. Демо — генерируется в памяти; релиз — /api/v1/admin/*.
abstract interface class AdminRepository {
  Future<List<OrderMessage>> orderComments(int orderId);
  Future<List<OrderMessage>> replyToOrder(int orderId, String text);

  /// Синхронные стартовые данные (только демо) — чтобы экран не мигал пустым состоянием.
  T? seed<T>();

  Future<List<AdminOrder>> orders({required bool full});
  Future<void> setStage(AdminOrder order, OrderStage stage);
  Future<FinanceData> finance(int days);
  Future<List<AdminProduct>> products();
  Future<List<AdminCategory>> categories();
  Future<AdminProduct> saveProduct(AdminProduct product, {required bool isNew});
  Future<AdminCategory> createCategory(String name, String slug);
  Future<AdminCategory> updateCategory(AdminCategory category);
  Future<String> importProducts(String filename, List<int> bytes);

  /// Действие над выделенными товарами; возвращает, сколько товаров затронуто.
  Future<int> bulkProducts(List<int> ids, BulkAction action, {int? categoryId});

  Future<List<AdminBrand>> brands();
  Future<AdminBrand> saveBrand(AdminBrand brand);

  /// Фирма уходит из списка и у всех её товаров.
  Future<void> deleteBrand(int id);

  /// Все товары в Excel: цены, остатки, ссылки на фото — поправить и загрузить обратно.
  Future<List<int>> exportProducts();

  /// Фото с компьютера → адрес для поля image_url (сервер проверит, уменьшит и пересохранит в WebP).
  /// kind: products — до 1200 px, banners — до 1800 px.
  Future<String> uploadProductImage(
    String filename,
    List<int> bytes, {
    String kind = 'products',
  });

  Future<ShopSettings> shopSettings();
  Future<ShopSettings> saveShopSettings(ShopSettings settings);
  Future<ReferralSettings> referralSettings();
  Future<ReferralSettings> saveReferralSettings(ReferralSettings settings);

  Future<List<AdminBanner>> banners();
  Future<AdminBanner> saveBanner(AdminBanner banner);
  Future<void> deleteBanner(int id);
  Future<void> reorderBanners(List<int> ids);

  Future<List<SupportThread>> supportThreads();
  Future<List<SupportMessage>> supportThread(int userId);
  Future<List<SupportMessage>> answerSupport(int userId, String text);

  /// Своё имя и телефон (видны в заказах и переписке).
  Future<void> updateMyProfile({required String name, required String phone});
  Future<List<AdminReview>> reviews();
  Future<void> moderate(int id, {required bool approve});
  Future<int> moderateMany(List<int> ids, {required bool approve});
  Future<List<TierConfig>> tiers();
  Future<void> createTier(TierConfig tier);
  Future<void> updateTier(TierConfig tier);
  Future<void> deleteTier(TierConfig tier);
  Future<List<StaffMember>> staff();

  Future<List<AdminStory>> stories();
  Future<AdminStory> saveStory(AdminStory story);
  Future<void> deleteStory(int id);
  Future<void> reorderStories(List<int> ids);

  /// true — удалён; false — у человека есть свои заказы: аккаунт оставлен, доступ в админку снят.
  Future<bool> deleteStaff(int id);
  Future<DeliveryZone> deliveryZone();

  /// lat/lng — точка, выбранная на карте; без них сервер найдёт адрес склада геокодером.
  Future<DeliveryZone> saveDeliveryZone(DeliveryZone zone, {bool pinned});
  Future<WorkHours> workHours();
  Future<WorkHours> saveWorkHours(WorkHours hours);

  /// Сервер приводит «@имя» и любые формы ссылки к https://t.me/… и https://instagram.com/….
  Future<ShopSocials> socials();
  Future<ShopSocials> saveSocials(ShopSocials socials);

  Future<List<B2BCompany>> companies();
  Future<void> decideCompany(int id, {required bool approve, String? note});

  /// Минимальная сумма заказа для оптовиков, ₽; 0 — без ограничения.
  Future<double> wholesaleMinOrder();
  Future<double> saveWholesaleMinOrder(double value);

  Future<List<CourierOrder>> courierOrders();
  Future<CourierOrder> takeOrder(int id);
  Future<CourierOrder> sendLocation(int id, double lat, double lng);
  Future<CourierOrder> emergency(int id, String reason);
  Future<CourierOrder> markDelivered(int id);
  Future<List<OrderMessage>> courierChat(int id);
  Future<List<OrderMessage>> courierSay(int id, String text);
  Future<void> createStaff({
    required String email,
    required String name,
    required String role,
    required String password,
  });
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AppConfig.isDemo ? DemoAdminRepository() : ApiAdminRepository(ref),
);

class ApiAdminRepository implements AdminRepository {
  ApiAdminRepository(this._ref);
  final Ref _ref;
  Dio get _dio => _ref.read(dioProvider);

  @override
  Future<List<OrderMessage>> orderComments(int orderId) => _wrap(
    () async => [
      for (final c in _list(
        await _dio.get<dynamic>('/api/v1/admin/orders/$orderId/comments'),
      ))
        OrderMessage.fromJson(c),
    ],
  );

  @override
  Future<List<OrderMessage>> replyToOrder(int orderId, String text) => _wrap(
    () async => [
      for (final c in _list(
        await _dio.post<dynamic>(
          '/api/v1/admin/orders/$orderId/comments',
          data: {'text': text},
        ),
      ))
        OrderMessage.fromJson(c),
    ],
  );

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
  T? seed<T>() => null;

  @override
  Future<List<AdminOrder>> orders({required bool full}) => _wrap(() async {
    // У сборщика нет orders:read_all — ему доступна только очередь сборки (без цен)
    final r = await _dio.get<dynamic>(
      full ? '/api/v1/admin/orders' : '/api/v1/staff/picking',
      queryParameters: {if (full) 'limit': 200},
    );
    return [for (final o in _list(r)) AdminOrder.fromJson(o)];
  });

  @override
  Future<void> setStage(AdminOrder order, OrderStage stage) => _wrap(
    () => _dio.patch<dynamic>(
      '/api/v1/staff/orders/${order.id}/status',
      data: {'status': stage.code},
    ),
  );

  @override
  Future<FinanceData> finance(int days) => _wrap(() async {
    final j = (await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/finance',
      queryParameters: {'days': days},
    )).data!;
    double d(Object? v) => double.parse(v.toString());
    return FinanceData([
      for (final x in (j['series'] as List).cast<Map<String, dynamic>>())
        DayFinance(
          DateTime.parse(x['day'] as String),
          d(x['revenue']),
          d(x['expenses']),
          x['orders'] as int,
        ),
    ], profitVisible: (j['current'] as Map)['profit'] != null);
  });

  @override
  Future<List<AdminProduct>> products() => _wrap(
    () async => [
      for (final p in _list(await _dio.get<dynamic>('/api/v1/admin/products')))
        AdminProduct.fromJson(p),
    ],
  );

  @override
  Future<List<AdminCategory>> categories() => _wrap(
    () async => [
      for (final c in _list(
        await _dio.get<dynamic>('/api/v1/admin/categories'),
      ))
        AdminCategory.fromJson(c),
    ],
  );

  @override
  Future<AdminProduct> saveProduct(AdminProduct p, {required bool isNew}) =>
      _wrap(() async {
        final r = isNew
            ? await _dio.post<Map<String, dynamic>>(
                '/api/v1/admin/products',
                data: p.toJson(),
              )
            : await _dio.patch<Map<String, dynamic>>(
                '/api/v1/admin/products/${p.id}',
                data: p.toJson()..remove('sku'),
              );
        return AdminProduct.fromJson(r.data!);
      });

  @override
  Future<AdminCategory> createCategory(String name, String slug) =>
      _wrap(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/api/v1/admin/categories',
          data: {'name': name, 'slug': slug},
        );
        return AdminCategory(r.data!['id'] as int, name, savedSlug: slug);
      });

  @override
  Future<AdminCategory> updateCategory(AdminCategory c) => _wrap(() async {
    await _dio.patch<dynamic>(
      '/api/v1/admin/categories/${c.id}',
      data: {
        'name': c.name,
        'slug': c.slug,
        'image_url': c.imageUrl,
        'is_visible': c.isVisible,
        'position': c.position,
        'description': c.description,
      },
    );
    return c;
  });

  @override
  Future<int> bulkProducts(
    List<int> ids,
    BulkAction action, {
    int? categoryId,
  }) => _wrap(() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/products/bulk',
      data: {'ids': ids, 'action': action.name, 'category_id': categoryId},
    );
    return r.data!['affected'] as int;
  });

  @override
  Future<List<AdminBrand>> brands() => _wrap(
    () async => [
      for (final b in _list(await _dio.get<dynamic>('/api/v1/admin/brands')))
        AdminBrand.fromJson(b),
    ],
  );

  @override
  Future<AdminBrand> saveBrand(AdminBrand b) => _wrap(() async {
    final body = {'name': b.name, 'logo_url': b.logoUrl};
    final r = b.id == null
        ? await _dio.post<Map<String, dynamic>>(
            '/api/v1/admin/brands',
            data: body,
          )
        : await _dio.put<Map<String, dynamic>>(
            '/api/v1/admin/brands/${b.id}',
            data: body,
          );
    return AdminBrand.fromJson(r.data!);
  });

  @override
  Future<void> deleteBrand(int id) =>
      _wrap(() => _dio.delete<dynamic>('/api/v1/admin/brands/$id'));

  @override
  Future<List<int>> exportProducts() => _wrap(
    () async => (await _dio.get<List<int>>(
      '/api/v1/admin/products/export',
      queryParameters: {'format': 'xlsx'},
      options: Options(responseType: ResponseType.bytes),
    )).data!,
  );

  @override
  Future<ShopSettings> shopSettings() => _wrap(
    () async => ShopSettings.fromJson(
      (await _dio.get<Map<String, dynamic>>('/api/v1/admin/settings/shop'))
          .data!,
    ),
  );

  @override
  Future<ShopSettings> saveShopSettings(ShopSettings s) => _wrap(
    () async => ShopSettings.fromJson(
      (await _dio.put<Map<String, dynamic>>(
        '/api/v1/admin/settings/shop',
        data: s.toJson(),
      )).data!,
    ),
  );

  @override
  Future<ReferralSettings> referralSettings() => _wrap(
    () async => ReferralSettings.fromJson(
      (await _dio.get<Map<String, dynamic>>('/api/v1/admin/settings/referral'))
          .data!,
    ),
  );

  @override
  Future<ReferralSettings> saveReferralSettings(ReferralSettings s) => _wrap(
    () async => ReferralSettings.fromJson(
      (await _dio.put<Map<String, dynamic>>(
        '/api/v1/admin/settings/referral',
        data: s.toJson(),
      )).data!,
    ),
  );

  @override
  Future<List<AdminBanner>> banners() => _wrap(
    () async => [
      for (final b in _list(await _dio.get<dynamic>('/api/v1/admin/banners')))
        AdminBanner.fromJson(b),
    ],
  );

  @override
  Future<AdminBanner> saveBanner(AdminBanner b) => _wrap(() async {
    final r = b.id == 0
        ? await _dio.post<Map<String, dynamic>>(
            '/api/v1/admin/banners',
            data: b.toJson(),
          )
        : await _dio.put<Map<String, dynamic>>(
            '/api/v1/admin/banners/${b.id}',
            data: b.toJson(),
          );
    return AdminBanner.fromJson(r.data!);
  });

  @override
  Future<void> deleteBanner(int id) =>
      _wrap(() => _dio.delete<dynamic>('/api/v1/admin/banners/$id'));

  @override
  Future<void> reorderBanners(List<int> ids) => _wrap(
    () => _dio.put<dynamic>('/api/v1/admin/banners-order', data: {'ids': ids}),
  );

  @override
  Future<List<SupportThread>> supportThreads() => _wrap(
    () async => [
      for (final t in _list(await _dio.get<dynamic>('/api/v1/admin/support')))
        SupportThread.fromJson(t),
    ],
  );

  @override
  Future<List<SupportMessage>> supportThread(int userId) => _wrap(
    () async => [
      for (final m in _list(
        await _dio.get<dynamic>('/api/v1/admin/support/$userId'),
      ))
        SupportMessage.fromJson(m),
    ],
  );

  @override
  Future<List<SupportMessage>> answerSupport(int userId, String text) => _wrap(
    () async => [
      for (final m in _list(
        await _dio.post<dynamic>(
          '/api/v1/admin/support/$userId',
          data: {'text': text},
        ),
      ))
        SupportMessage.fromJson(m),
    ],
  );

  @override
  Future<void> updateMyProfile({required String name, required String phone}) =>
      _wrap(
        () => _dio.patch<dynamic>(
          '/api/v1/me/profile',
          data: {'full_name': name, 'phone': phone},
        ),
      );

  @override
  Future<String> uploadProductImage(
    String filename,
    List<int> bytes, {
    String kind = 'products',
  }) => _wrap(() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/uploads/product-image',
      queryParameters: {'kind': kind},
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
    );
    return r.data!['url'] as String;
  });

  @override
  Future<String> importProducts(
    String filename,
    List<int> bytes,
  ) => _wrap(() async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/products/import',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
    );
    final j = r.data!;
    final photos = (j['images_downloaded'] as int? ?? 0) > 0
        ? ', фото загружено: ${j['images_downloaded']}'
        : '';
    final cats = (j['categories_updated'] as int? ?? 0) > 0
        ? ', категорий: ${j['categories_updated']}'
        : '';
    return 'Новых: ${j['created']}, обновлено: ${j['updated']}$photos$cats, с ошибками: ${j['failed']}';
  });

  @override
  Future<List<AdminReview>> reviews() => _wrap(
    () async => [
      for (final r in _list(await _dio.get<dynamic>('/api/v1/admin/reviews')))
        AdminReview.fromJson(r),
    ],
  );

  @override
  Future<int> moderateMany(List<int> ids, {required bool approve}) => _wrap(
    () async =>
        (await _dio.post<Map<String, dynamic>>(
              '/api/v1/admin/reviews/moderate-bulk',
              data: {'ids': ids, 'approve': approve},
            )).data!['updated']
            as int,
  );

  @override
  Future<void> moderate(int id, {required bool approve}) => _wrap(
    () => _dio.post<dynamic>(
      '/api/v1/admin/reviews/$id/moderate',
      data: {'approve': approve},
    ),
  );

  @override
  Future<List<TierConfig>> tiers() => _wrap(
    () async => [
      for (final t in _list(
        await _dio.get<dynamic>('/api/v1/admin/loyalty-tiers'),
      ))
        TierConfig.fromJson(t),
    ],
  );

  Map<String, dynamic> _tierJson(TierConfig t) => {
    'name': t.name,
    'min_total_spent': t.threshold.toStringAsFixed(2),
    'discount_type': 'percent',
    'discount_value': t.percent.toStringAsFixed(2),
    'color_hex':
        '#${(t.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
  };

  @override
  Future<void> updateTier(TierConfig t) => _wrap(
    () => _dio.put<dynamic>(
      '/api/v1/admin/loyalty-tiers/${t.id}',
      data: _tierJson(t),
    ),
  );

  @override
  Future<void> deleteTier(TierConfig t) =>
      _wrap(() => _dio.delete<dynamic>('/api/v1/admin/loyalty-tiers/${t.id}'));

  @override
  Future<void> createTier(TierConfig t) => _wrap(
    () => _dio.post<dynamic>(
      '/api/v1/admin/loyalty-tiers',
      data: {
        'name': t.name,
        'min_total_spent': t.threshold.toStringAsFixed(2),
        'discount_type': 'percent',
        'discount_value': t.percent.toStringAsFixed(2),
        'color_hex':
            '#${(t.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      },
    ),
  );

  @override
  Future<DeliveryZone> deliveryZone() => _wrap(
    () async => DeliveryZone.fromJson(
      (await _dio.get<Map<String, dynamic>>('/api/v1/admin/settings/delivery'))
          .data!,
    ),
  );

  @override
  Future<DeliveryZone> saveDeliveryZone(DeliveryZone z, {bool pinned = true}) =>
      _wrap(
        () async => DeliveryZone.fromJson(
          (await _dio.put<Map<String, dynamic>>(
            '/api/v1/admin/settings/delivery',
            data: {
              'radius_km': z.radiusKm,
              'enabled': z.enabled,
              'store_address': z.storeAddress,
              'cities': z.cities,
              if (pinned) ...{'lat': z.lat, 'lng': z.lng},
            },
          )).data!,
        ),
      );

  Future<CourierOrder> _courierPost(int id, String action, [Object? data]) =>
      _wrap(
        () async => CourierOrder.fromJson(
          (await _dio.post<Map<String, dynamic>>(
            '/api/v1/courier/orders/$id/$action',
            data: data,
          )).data!,
        ),
      );

  @override
  Future<List<CourierOrder>> courierOrders() => _wrap(
    () async => [
      for (final o in _list(await _dio.get<dynamic>('/api/v1/courier/orders')))
        CourierOrder.fromJson(o),
    ],
  );

  @override
  Future<CourierOrder> takeOrder(int id) => _courierPost(id, 'take');

  @override
  Future<CourierOrder> sendLocation(int id, double lat, double lng) =>
      _courierPost(id, 'location', {'lat': lat, 'lng': lng});

  @override
  Future<CourierOrder> emergency(int id, String reason) =>
      _courierPost(id, 'emergency', {'reason': reason});

  @override
  Future<CourierOrder> markDelivered(int id) => _courierPost(id, 'delivered');

  @override
  Future<List<OrderMessage>> courierChat(int id) => _wrap(
    () async => [
      for (final c in _list(
        await _dio.get<dynamic>('/api/v1/courier/orders/$id/chat'),
      ))
        OrderMessage.fromJson(c),
    ],
  );

  @override
  Future<List<OrderMessage>> courierSay(int id, String text) => _wrap(
    () async => [
      for (final c in _list(
        await _dio.post<dynamic>(
          '/api/v1/courier/orders/$id/chat',
          data: {'text': text},
        ),
      ))
        OrderMessage.fromJson(c),
    ],
  );

  @override
  Future<WorkHours> workHours() => _wrap(
    () async => WorkHours.fromJson(
      (await _dio.get<Map<String, dynamic>>('/api/v1/admin/settings/hours'))
          .data!,
    ),
  );

  @override
  Future<WorkHours> saveWorkHours(WorkHours h) => _wrap(
    () async => WorkHours.fromJson(
      (await _dio.put<Map<String, dynamic>>(
        '/api/v1/admin/settings/hours',
        data: h.toJson(),
      )).data!,
    ),
  );

  @override
  Future<ShopSocials> socials() => _wrap(
    () async => ShopSocials.fromJson(
      (await _dio.get<Map<String, dynamic>>('/api/v1/admin/settings/socials'))
          .data!,
    ),
  );

  @override
  Future<ShopSocials> saveSocials(ShopSocials s) => _wrap(
    () async => ShopSocials.fromJson(
      (await _dio.put<Map<String, dynamic>>(
        '/api/v1/admin/settings/socials',
        data: s.toJson(),
      )).data!,
    ),
  );

  @override
  Future<List<B2BCompany>> companies() => _wrap(
    () async => [
      for (final c in _list(
        await _dio.get<dynamic>('/api/v1/admin/b2b-accounts'),
      ))
        B2BCompany.fromJson(c),
    ],
  );

  @override
  Future<void> decideCompany(int id, {required bool approve, String? note}) =>
      _wrap(
        () => _dio.post<dynamic>(
          '/api/v1/admin/b2b-accounts/$id/decision',
          data: {'approve': approve, 'note': note},
        ),
      );

  @override
  Future<double> wholesaleMinOrder() => _wrap(
    () async => double.parse(
      (await _dio.get<Map<String, dynamic>>('/api/v1/admin/settings/wholesale'))
              .data!['min_order']
          as String,
    ),
  );

  @override
  Future<double> saveWholesaleMinOrder(double value) => _wrap(
    () async => double.parse(
      (await _dio.put<Map<String, dynamic>>(
            '/api/v1/admin/settings/wholesale',
            data: {'min_order': value.toStringAsFixed(2)},
          )).data!['min_order']
          as String,
    ),
  );

  @override
  Future<bool> deleteStaff(int id) => _wrap(
    () async =>
        (await _dio.delete<Map<String, dynamic>>('/api/v1/admin/staff/$id'))
                .data!['deleted']
            as bool,
  );

  @override
  Future<List<AdminStory>> stories() => _wrap(
    () async => [
      for (final s in _list(await _dio.get<dynamic>('/api/v1/admin/stories')))
        AdminStory.fromJson(s),
    ],
  );

  @override
  Future<AdminStory> saveStory(AdminStory s) => _wrap(() async {
    final r = s.id == 0
        ? await _dio.post<Map<String, dynamic>>(
            '/api/v1/admin/stories',
            data: s.toJson(),
          )
        : await _dio.put<Map<String, dynamic>>(
            '/api/v1/admin/stories/${s.id}',
            data: s.toJson(),
          );
    return AdminStory.fromJson(r.data!);
  });

  @override
  Future<void> deleteStory(int id) =>
      _wrap(() => _dio.delete<dynamic>('/api/v1/admin/stories/$id'));

  @override
  Future<void> reorderStories(List<int> ids) => _wrap(
    () => _dio.put<dynamic>('/api/v1/admin/stories-order', data: {'ids': ids}),
  );

  @override
  Future<List<StaffMember>> staff() => _wrap(
    () async => [
      for (final s in _list(await _dio.get<dynamic>('/api/v1/admin/staff')))
        StaffMember.fromJson(s),
    ],
  );

  @override
  Future<void> createStaff({
    required String email,
    required String name,
    required String role,
    required String password,
  }) => _wrap(
    () => _dio.post<dynamic>(
      '/api/v1/admin/staff',
      data: {
        'email': email,
        'full_name': name,
        'role': role,
        'password': password,
      },
    ),
  );
}

/// Доля себестоимости по категориям (для расчёта маржи в демо).
const _costRatio = {
  1: .62,
  2: .65,
  3: .6,
  4: .5,
  5: .7,
  6: .68,
  7: .72,
  8: .45,
  9: .68,
  10: .55,
  11: .6,
  12: .75,
};

double demoCostOf(DemoItem i) =>
    (i.price * (_costRatio[i.categoryId] ?? .65)).roundToDouble();

AdminProduct _fromDemo(DemoItem i) => AdminProduct(
  id: i.id,
  sku: 'GR-${i.id.toString().padLeft(4, '0')}',
  name: i.name,
  unit: i.unit,
  brand: i.brand,
  imageUrl: ingredientImage(i.image),
  categoryId: i.categoryId,
  price: i.price,
  cost: demoCostOf(i),
  wholesalePrice: (i.price * 0.85).roundToDouble(),
  stock: i.stock,
  isHit: i.badges.isNotEmpty,
);

const _customers = [
  'Мария Кузнецова',
  'Алексей Иванов',
  'Ольга Соколова',
  'Дмитрий Попов',
  'Елена Новикова',
  'Кафе «Зелень»',
  'Сергей Морозов',
  'Наталья Волкова',
  'Ресторан «Гусь»',
  'Андрей Лебедев',
  'Татьяна Козлова',
  'Павел Орлов',
];
const _streets = [
  'ул. Тверская',
  'Ленинский пр-т',
  'ул. Арбат',
  'Кутузовский пр-т',
  'ул. Профсоюзная',
  'ул. Мясницкая',
];
const _comments = [
  null,
  'Позвонить за 30 минут',
  null,
  'Бананы не слишком спелые',
  null,
  'Оставить у двери',
];

class DemoAdminRepository implements AdminRepository {
  final Map<int, List<OrderMessage>> _messages = {};

  List<OrderMessage> _thread(int orderId) => _messages.putIfAbsent(orderId, () {
    final o = _orders.where((x) => x.id == orderId).firstOrNull;
    return [
      if (o?.comment case final c?)
        OrderMessage(
          text: c,
          fromStaff: false,
          author: o!.customer,
          createdAt: o.createdAt.add(const Duration(minutes: 3)),
        ),
    ];
  });

  @override
  Future<List<OrderMessage>> orderComments(int orderId) async =>
      List.of(_thread(orderId));

  @override
  Future<List<OrderMessage>> replyToOrder(int orderId, String text) async {
    _thread(orderId).add(
      OrderMessage(
        text: text,
        fromStaff: true,
        author: 'Магазин',
        createdAt: DateTime.now(),
      ),
    );
    return List.of(_thread(orderId));
  }

  late final List<AdminOrder> _orders = _generateOrders();
  late final List<AdminProduct> _products = [
    for (final i in demoItems) _fromDemo(i),
  ];
  late final List<AdminCategory> _categories = [
    for (final c in demoCategories) AdminCategory(c.id, c.name),
    const AdminCategory(90, 'Бакалея', savedSlug: 'bakaleya', isVisible: false),
    const AdminCategory(
      91,
      'Бытовая химия',
      savedSlug: 'bytovaya-himiya',
      isVisible: false,
    ),
  ];
  late final FinanceData _finance = _generateFinance();
  late final List<TierConfig> _tiers = [
    const TierConfig('Bronze', 0, 0, Color(0xFFB45309), 1840, id: 1),
    const TierConfig('Silver', 10000, 3, Color(0xFF64748B), 612, id: 2),
    const TierConfig('Gold', 30000, 5, Color(0xFFCA8A04), 187, id: 3),
    const TierConfig('Platinum', 75000, 8, AppColors.brand, 41, id: 4),
  ];

  /// Демо: 30 отзывов с разными оценками — чтобы было что фильтровать и одобрять пачкой.
  late final List<AdminReview> _reviews = () {
    const texts = {
      5: [
        'Отличное качество, свежее, возьму ещё!',
        'Курьер приехал вовремя, всё целое. Спасибо!',
        'Лучшее, что пробовала в этом году.',
      ],
      4: [
        'Хорошо, но упаковка могла быть получше.',
        'Вкусно, чуть дороже, чем ожидал.',
      ],
      3: ['Нормально, ничего особенного.', 'Средне — бывало и лучше.'],
      2: [
        'Пара штук была помята, неприятно.',
        'Привезли не ту фасовку, пришлось менять.',
      ],
      1: ['Испорченный товар, верните деньги!', 'Ужасно, больше не закажу.'],
    };
    const authors = [
      'Мария К.', 'Алексей И.', 'Ольга С.', 'Дмитрий П.', 'Елена Н.', //
      'Сергей М.', 'Наталья В.', 'Андрей Л.', 'Татьяна К.', 'Павел О.',
    ];
    const ratings = [5, 5, 4, 1, 5, 3, 2, 5, 4, 5, 1, 4, 5, 2, 3];
    final rnd = Random(11);
    final now = DateTime.now();
    return [
      for (var i = 0; i < 30; i++)
        () {
          final r = ratings[i % ratings.length];
          final item = demoItems[rnd.nextInt(demoItems.length)];
          final options = texts[r]!;
          return AdminReview(
            id: i + 1,
            author: authors[i % authors.length],
            productName: item.name,
            productImage: ingredientImage(item.image),
            rating: r,
            text: options[i % options.length],
            state: i < 18
                ? ReviewState.pending
                : (r >= 3 ? ReviewState.approved : ReviewState.rejected),
            createdAt: now.subtract(Duration(hours: i * 5 + rnd.nextInt(4))),
          );
        }(),
    ];
  }();
  final List<StaffMember> _staff = [
    const StaffMember(
      id: 1,
      email: 'owner@saasshop.local',
      name: 'Хабиб Зухуров',
      role: 'owner',
    ),
    const StaffMember(
      id: 2,
      email: 'manager@saasshop.local',
      name: 'Анна Смирнова',
      role: 'manager',
    ),
    const StaffMember(
      id: 3,
      email: 'picker@saasshop.local',
      name: 'Игорь Петров',
      role: 'picker',
    ),
  ];

  @override
  T? seed<T>() => switch (T) {
    const (List<AdminOrder>) => _orders as T,
    const (List<AdminProduct>) => _products as T,
    const (List<AdminCategory>) => _categories as T,
    const (List<AdminReview>) => _reviews as T,
    const (List<TierConfig>) => _tiers as T,
    const (List<StaffMember>) => _staff as T,
    const (List<AdminStory>) => _stories as T,
    const (FinanceData) => _finance as T,
    _ => null,
  };

  static List<AdminOrder> _generateOrders() {
    final rnd = Random(7);
    final now = DateTime.now();
    return [
      for (var i = 0; i < 28; i++)
        () {
          final customer = _customers[rnd.nextInt(_customers.length)];
          final b2b =
              customer.startsWith('Кафе') || customer.startsWith('Ресторан');
          final picked = <int>{};
          final lines = <OrderLine>[];
          for (var k = 0; k < 2 + rnd.nextInt(5); k++) {
            final item = demoItems[rnd.nextInt(demoItems.length)];
            if (picked.add(item.id)) {
              lines.add(
                OrderLine(
                  productId: item.id,
                  name: item.name,
                  unit: item.unit,
                  imageUrl: ingredientImage(item.image),
                  qty: b2b ? 5 + rnd.nextInt(15) : 1 + rnd.nextInt(3),
                  price: item.price * (b2b ? .85 : 1),
                  cost: demoCostOf(item),
                ),
              );
            }
          }
          final hoursAgo = i * 4 + rnd.nextInt(3);
          final stage = switch (hoursAgo) {
            < 3 => OrderStage.newOrder,
            < 8 => OrderStage.picking,
            < 14 => OrderStage.shipped,
            _ => i % 11 == 5 ? OrderStage.cancelled : OrderStage.delivered,
          };
          final total = lines.fold(0.0, (a, l) => a + l.total);
          final online = i % 3 != 2;
          final paymentStatus = switch ((online, stage)) {
            (true, OrderStage.newOrder) when i == 1 => 'pending',
            (true, _) => 'paid',
            (false, OrderStage.delivered) => 'paid',
            _ => 'not_required',
          };
          return AdminOrder(
            paymentMethod: online ? 'card_online' : 'cash',
            paymentStatus: paymentStatus,
            id: 28 - i,
            number: '№${10268 - i}',
            customer: customer,
            phone:
                '+7 9${rnd.nextInt(90) + 10} ${rnd.nextInt(900) + 100}-${rnd.nextInt(90) + 10}-${rnd.nextInt(90) + 10}',
            address:
                '${_streets[rnd.nextInt(_streets.length)]}, ${3 + rnd.nextInt(80)}',
            createdAt: now.subtract(
              Duration(hours: hoursAgo, minutes: rnd.nextInt(60)),
            ),
            stage: stage,
            lines: lines,
            isB2B: b2b,
            comment: _comments[rnd.nextInt(_comments.length)],
            total: total,
            cost: lines.fold(0.0, (a, l) => a + l.costTotal),
            delivery: total >= 1500 ? 120 : 90,
          );
        }(),
    ];
  }

  /// 60 дней истории: недельная сезонность (пик в пятницу–субботу) + плавный рост.
  static FinanceData _generateFinance() {
    final rnd = Random(3);
    final today = DateUtils.dateOnly(DateTime.now());
    return FinanceData([
      for (var i = 59; i >= 0; i--)
        () {
          final day = today.subtract(Duration(days: i));
          final weekend = day.weekday >= 5 ? 1.35 : 1.0;
          final growth = 1 + (59 - i) * 0.006;
          final orders = ((38 + rnd.nextInt(14)) * weekend * growth).round();
          final revenue = orders * (1450 + rnd.nextInt(400)).toDouble();
          return DayFinance(
            day,
            revenue,
            revenue * (0.74 + rnd.nextDouble() * 0.06),
            orders,
          );
        }(),
    ]);
  }

  @override
  Future<List<AdminOrder>> orders({required bool full}) async => _orders;
  @override
  Future<void> setStage(AdminOrder order, OrderStage stage) async {}
  @override
  Future<FinanceData> finance(int days) async => _finance;
  @override
  Future<List<AdminProduct>> products() async => _products;
  @override
  Future<List<AdminCategory>> categories() async => _categories;
  @override
  Future<AdminProduct> saveProduct(
    AdminProduct p, {
    required bool isNew,
  }) async {
    // демо: сохраняем в памяти, чтобы правки не пропадали при перезаходе
    final saved = isNew
        ? AdminProduct(
            id: 1000 + _products.length,
            sku: p.sku,
            name: p.name,
            price: p.price,
            cost: p.cost,
            stock: p.stock,
            unit: p.unit,
            brand: p.brand,
            imageUrl: p.imageUrl,
            categoryId: p.categoryId,
            isHit: p.isHit,
          )
        : p;
    final i = _products.indexWhere((x) => x.id == saved.id);
    i < 0 ? _products.insert(0, saved) : _products[i] = saved;
    return saved;
  }

  @override
  Future<AdminCategory> createCategory(String name, String slug) async {
    final c = AdminCategory(100 + _categories.length, name, savedSlug: slug);
    _categories.add(c);
    return c;
  }

  @override
  Future<AdminCategory> updateCategory(AdminCategory c) async {
    final i = _categories.indexWhere((x) => x.id == c.id);
    if (i >= 0) _categories[i] = c;
    return c;
  }

  @override
  Future<int> bulkProducts(
    List<int> ids,
    BulkAction action, {
    int? categoryId,
  }) async {
    final set = ids.toSet();
    if (action == BulkAction.delete) {
      _products.removeWhere((p) => set.contains(p.id));
      return set.length;
    }
    for (final (i, p) in _products.indexed) {
      if (!set.contains(p.id)) continue;
      _products[i] = switch (action) {
        BulkAction.hide => p.copyWith(isActive: false),
        BulkAction.show => p.copyWith(isActive: true),
        _ => p.copyWith(
          categoryId: categoryId,
          clearCategory: categoryId == null,
        ),
      };
    }
    return set.length;
  }

  late final List<AdminBrand> _brands = [
    for (final (i, name) in {for (final p in _products) ?p.brand}.indexed)
      AdminBrand(
        id: i + 1,
        name: name,
        productsCount: _products.where((p) => p.brand == name).length,
      ),
  ];

  @override
  Future<List<AdminBrand>> brands() async =>
      List.of(_brands)..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<AdminBrand> saveBrand(AdminBrand b) async {
    final saved = AdminBrand(
      id: b.id ?? _brands.fold<int>(0, (m, x) => max(m, x.id ?? 0)) + 1,
      name: b.name,
      logoUrl: b.logoUrl,
      productsCount: b.productsCount,
    );
    final i = _brands.indexWhere((x) => x.id == saved.id);
    i < 0 ? _brands.add(saved) : _brands[i] = saved;
    return saved;
  }

  @override
  Future<void> deleteBrand(int id) async =>
      _brands.removeWhere((b) => b.id == id);

  @override
  Future<List<int>> exportProducts() async => utf8.encode(
    'Артикул;Название;Цена\n${[for (final p in _products) '${p.sku};${p.name};${p.price}'].join('\n')}',
  );

  ShopSettings _shop = const ShopSettings();
  @override
  Future<ShopSettings> shopSettings() async => _shop;
  @override
  Future<ShopSettings> saveShopSettings(ShopSettings s) async => _shop = s;

  ReferralSettings _referral = const ReferralSettings();
  @override
  Future<ReferralSettings> referralSettings() async => _referral;
  @override
  Future<ReferralSettings> saveReferralSettings(ReferralSettings s) async =>
      _referral = s;

  late final List<AdminBanner> _banners = [
    AdminBanner(
      id: 1,
      title: 'Неделя ягод',
      text: 'Клубника и голубика со скидкой до 20%',
      imageUrl: ingredientImage('strawberries'),
      buttonLabel: 'Смотреть',
      linkUrl: '/promo',
    ),
    const AdminBanner(
      id: 2,
      title: 'Оптовые цены для кафе',
      text: 'Подключим ваш бизнес за день',
      buttonLabel: 'Оставить заявку',
      linkUrl: '/business',
      theme: BannerTheme.cream,
      isActive: false,
    ),
  ];
  @override
  Future<List<AdminBanner>> banners() async => List.of(_banners);
  @override
  Future<AdminBanner> saveBanner(AdminBanner b) async {
    final saved = b.id == 0
        ? b.copyWith(id: _banners.fold(0, (m, x) => max(m, x.id)) + 1)
        : b;
    final i = _banners.indexWhere((x) => x.id == saved.id);
    i < 0 ? _banners.add(saved) : _banners[i] = saved;
    return saved;
  }

  @override
  Future<void> deleteBanner(int id) async =>
      _banners.removeWhere((x) => x.id == id);
  @override
  Future<void> reorderBanners(List<int> ids) async =>
      _banners.sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));

  late final Map<int, List<SupportMessage>> _support = {
    51: [
      SupportMessage(
        id: 1,
        text: 'Здравствуйте! Можно привезти заказ после 20:00?',
        fromStaff: false,
        author: 'Вы',
        createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
      ),
    ],
    52: [
      SupportMessage(
        id: 2,
        text: 'Добавьте, пожалуйста, гречку «Мистраль»',
        fromStaff: false,
        author: 'Вы',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      SupportMessage(
        id: 3,
        text: 'Спасибо! Завезём на этой неделе',
        fromStaff: true,
        author: 'Анна',
        createdAt: DateTime.now().subtract(const Duration(hours: 20)),
      ),
    ],
  };
  final Set<int> _supportRead = {52};
  static const _supportPeople = {51: 'Мария Кузнецова', 52: 'Олег Смирнов'};

  @override
  Future<List<SupportThread>> supportThreads() async => [
    for (final e in _support.entries)
      SupportThread(
        userId: e.key,
        name: _supportPeople[e.key] ?? 'Покупатель',
        phone: '+7916000${e.key}00',
        lastText: e.value.last.text,
        lastAt: e.value.last.createdAt,
        lastFromStaff: e.value.last.fromStaff,
        unread: _supportRead.contains(e.key)
            ? 0
            : e.value.where((m) => !m.fromStaff).length,
      ),
  ]..sort((a, b) => b.lastAt.compareTo(a.lastAt));

  @override
  Future<List<SupportMessage>> supportThread(int userId) async {
    _supportRead.add(userId);
    return List.of(_support[userId] ?? const []);
  }

  @override
  Future<List<SupportMessage>> answerSupport(int userId, String text) async {
    final thread = _support.putIfAbsent(userId, () => []);
    thread.add(
      SupportMessage(
        id: DateTime.now().microsecondsSinceEpoch,
        text: text,
        fromStaff: true,
        author: 'Поддержка',
        createdAt: DateTime.now(),
      ),
    );
    _supportRead.add(userId);
    return List.of(thread);
  }

  @override
  Future<void> updateMyProfile({
    required String name,
    required String phone,
  }) async {}

  @override
  Future<String> uploadProductImage(
    String filename,
    List<int> bytes, {
    String kind = 'products',
  }) async {
    // демо без сервера: картинка живёт в памяти вкладки (data:-адрес)
    final ext = filename.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'png' : (ext == 'webp' ? 'webp' : 'jpeg');
    return 'data:image/$mime;base64,${base64Encode(bytes)}';
  }

  @override
  Future<String> importProducts(String filename, List<int> bytes) async =>
      'Демо-режим: файл $filename (${(bytes.length / 1024).toStringAsFixed(0)} КБ) проверен, но не загружен';
  @override
  Future<List<AdminReview>> reviews() async => _reviews;
  @override
  Future<void> moderate(int id, {required bool approve}) async =>
      moderateMany([id], approve: approve);
  @override
  Future<int> moderateMany(List<int> ids, {required bool approve}) async {
    final set = ids.toSet();
    for (var i = 0; i < _reviews.length; i++) {
      if (set.contains(_reviews[i].id)) {
        _reviews[i] = _reviews[i].withState(
          approve ? ReviewState.approved : ReviewState.rejected,
        );
      }
    }
    return set.length;
  }

  @override
  Future<List<TierConfig>> tiers() async =>
      [..._tiers]..sort((a, b) => a.threshold.compareTo(b.threshold));
  @override
  Future<void> createTier(TierConfig t) async => _tiers.add(
    // демо: держим в памяти, чтобы правки не пропадали
    TierConfig(
      t.name,
      t.threshold,
      t.percent,
      t.color,
      0,
      id: _tiers.fold(0, (m, x) => max(m, x.id ?? 0)) + 1,
    ),
  );
  @override
  Future<void> updateTier(TierConfig tier) async {
    final i = _tiers.indexWhere((x) => x.id == tier.id);
    if (i >= 0) _tiers[i] = tier;
  }

  @override
  Future<void> deleteTier(TierConfig tier) async =>
      _tiers.removeWhere((x) => x.id == tier.id);
  @override
  Future<List<StaffMember>> staff() async => List.of(_staff);

  late final List<AdminStory> _stories = [
    for (final (i, (title, color, img, headline)) in const [
      ('Сезон ягод', Color(0xFFE11D48), 'Strawberries', 'Клубника −20%'),
      ('Фермерское', Color(0xFF16A34A), 'Carrots', 'Овощи от фермы Иванова'),
      ('Рецепт дня', Color(0xFFD97706), 'Spaghetti', 'Паста помодоро'),
      ('За 2 часа', Color(0xFF0891B2), 'Lemon', 'Экспресс-доставка'),
    ].indexed)
      AdminStory(
        id: i + 1,
        title: title,
        color: color,
        coverUrl: ingredientImage(img),
        slides: [
          StorySlideData(imageUrl: ingredientImage(img), headline: headline),
        ],
      ),
  ];
  @override
  Future<List<AdminStory>> stories() async => List.of(_stories);
  @override
  Future<AdminStory> saveStory(AdminStory s) async {
    final saved = s.id == 0
        ? s.copyWith(id: _stories.fold(0, (m, x) => max(m, x.id)) + 1)
        : s;
    final i = _stories.indexWhere((x) => x.id == saved.id);
    i < 0 ? _stories.add(saved) : _stories[i] = saved;
    return saved;
  }

  @override
  Future<void> deleteStory(int id) async =>
      _stories.removeWhere((x) => x.id == id);
  @override
  Future<void> reorderStories(List<int> ids) async =>
      _stories.sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));
  @override
  Future<bool> deleteStaff(int id) async {
    final s = _staff.firstWhere((x) => x.id == id);
    final owners = _staff.where((x) => x.role == 'owner').length;
    if (s.role == 'owner' && owners <= 1) {
      throw ApiException('Нельзя удалить последнего владельца', status: 409);
    }
    _staff.removeWhere((x) => x.id == id);
    return true;
  }

  DeliveryZone _zone = DeliveryZone.moscow;
  @override
  Future<DeliveryZone> deliveryZone() async => _zone;
  @override
  Future<DeliveryZone> saveDeliveryZone(
    DeliveryZone z, {
    bool pinned = true,
  }) async {
    DemoDeliveryChecker.centerLat = z.lat;
    DemoDeliveryChecker.centerLng = z.lng;
    DemoDeliveryChecker.radiusKm = z.radiusKm;
    DemoDeliveryChecker.enabled = z.enabled;
    DemoDeliveryChecker.cities = z.cities;
    return _zone = z;
  }

  // Курьер (демо): три заказа в пути по Москве, курьер стартует со склада
  late final List<CourierOrder> _courier = [
    const CourierOrder(
      id: 9001,
      number: '№10271',
      customerName: 'Ольга',
      address: 'Москва, Кутузовский пр-т, 24, кв. 51, подъезд 3',
      note: 'Позвонить в домофон, собака лает — не пугайтесь',
      itemsCount: 6,
      total: 2140,
      cashToCollect: 2140,
      phoneMasked: '+7 ••• •••-••-18',
      mine: true,
      destLat: 55.7427,
      destLng: 37.5442,
    ),
    const CourierOrder(
      id: 9002,
      number: '№10272',
      customerName: 'Дмитрий',
      address: 'Москва, ул. Профсоюзная, 56, кв. 12',
      itemsCount: 3,
      total: 1290,
      phoneMasked: '+7 ••• •••-••-04',
      mine: false,
      destLat: 55.6703,
      destLng: 37.5527,
    ),
    const CourierOrder(
      id: 9003,
      number: '№10273',
      customerName: 'Кафе «Зелень»',
      address: 'Москва, ул. Мясницкая, 13с3',
      note: 'Вход со двора, к служебной двери',
      itemsCount: 24,
      total: 8650,
      phoneMasked: '+7 ••• •••-••-77',
      mine: false,
      destLat: 55.7621,
      destLng: 37.6352,
    ),
  ];
  static const _demoPhones = {
    9001: '+7 916 555-12-18',
    9002: '+7 925 301-77-04',
    9003: '+7 495 777-20-77',
  };
  final Map<int, (double, double)> _courierPos = {};
  final Map<int, List<OrderMessage>> _courierChats = {
    9001: [
      OrderMessage(
        text: 'Здравствуйте! Код домофона 51К, 7 этаж',
        fromStaff: false,
        author: 'Ольга',
        createdAt: DateTime.now().subtract(const Duration(minutes: 6)),
      ),
    ],
  };

  CourierOrder _replaceCourier(CourierOrder o) {
    final i = _courier.indexWhere((x) => x.id == o.id);
    _courier[i] = o;
    return o;
  }

  CourierOrder _courierById(int id) => _courier.firstWhere((x) => x.id == id);

  /// Курьер «едет»: каждая отправка геопозиции приближает его к адресу на 40%.
  (double, double) demoNextPosition(int id) {
    final o = _courierById(id);
    final (lat, lng) =
        _courierPos[id] ??
        (DemoDeliveryChecker.centerLat, DemoDeliveryChecker.centerLng);
    return (lat + (o.destLat! - lat) * .4, lng + (o.destLng! - lng) * .4);
  }

  @override
  Future<List<CourierOrder>> courierOrders() async => [
    for (final o in _courier)
      if (!o.delivered) o,
  ];

  @override
  Future<CourierOrder> takeOrder(int id) async =>
      _replaceCourier(_courierById(id).copyWith(mine: true));

  @override
  Future<CourierOrder> sendLocation(int id, double lat, double lng) async {
    _courierPos[id] = (lat, lng);
    final o = _courierById(id);
    final d = haversineKm(lat, lng, o.destLat!, o.destLng!);
    final near = d <= 1;
    return _replaceCourier(
      o.copyWith(
        distanceKm: (d * 100).round() / 100,
        phone: near ? _demoPhones[id] : null,
        phoneRevealReason: near && o.phone == null
            ? 'Курьер рядом с адресом (${d.toStringAsFixed(1)} км)'
            : null,
      ),
    );
  }

  @override
  Future<CourierOrder> emergency(int id, String reason) async {
    (_courierChats[id] ??= []).add(
      OrderMessage(
        text: 'Курьер открыл ваш номер телефона. Причина: $reason',
        fromStaff: true,
        author: 'Курьер Руслан',
        createdAt: DateTime.now(),
      ),
    );
    return _replaceCourier(
      _courierById(id)
          .copyWith(phone: _demoPhones[id], phoneRevealReason: 'ЧП: $reason'),
    );
  }

  @override
  Future<CourierOrder> markDelivered(int id) async =>
      _replaceCourier(_courierById(id).copyWith(delivered: true));

  @override
  Future<List<OrderMessage>> courierChat(int id) async =>
      List.of(_courierChats[id] ?? const []);

  @override
  Future<List<OrderMessage>> courierSay(int id, String text) async {
    final chat = _courierChats[id] ??= [];
    chat.add(
      OrderMessage(
        text: text,
        fromStaff: true,
        author: 'Курьер Руслан',
        createdAt: DateTime.now(),
      ),
    );
    // покупатель «отвечает» (демо)
    chat.add(
      OrderMessage(
        text: 'Хорошо, жду',
        fromStaff: false,
        author: _courierById(id).customerName,
        createdAt: DateTime.now(),
      ),
    );
    return List.of(chat);
  }

  WorkHours _hours = WorkHours.standard;
  @override
  Future<WorkHours> workHours() async => _hours;
  @override
  Future<WorkHours> saveWorkHours(WorkHours h) async {
    if (h.end.compareTo(h.start) <= 0) {
      throw ApiException('Время закрытия должно быть позже открытия');
    }
    final days = [...h.days]..sort();
    return _hours = WorkHours(
      days: days,
      start: h.start,
      end: h.end,
      text: _hoursText(days, h.start, h.end),
    );
  }

  static String _hoursText(List<int> days, String start, String end) {
    if (days.isEmpty) return 'временно не работаем';
    final time = 'с $start до $end';
    if (days.length == 7) return 'ежедневно $time';
    final runs = <List<int>>[];
    for (final d in days) {
      if (runs.isNotEmpty && d == runs.last.last + 1) {
        runs.last.add(d);
      } else {
        runs.add([d]);
      }
    }
    final n = WorkHours.dayNames;
    final parts = [
      for (final r in runs)
        r.length == 1
            ? n[r.first]
            : '${n[r.first]}${r.length > 2 ? '–' : ', '}${n[r.last]}',
    ];
    return '${parts.join(', ')} $time';
  }

  ShopSocials _socials = const ShopSocials();
  @override
  Future<ShopSocials> socials() async => _socials;
  @override
  Future<ShopSocials> saveSocials(ShopSocials s) async =>
      _socials = ShopSocials(
        telegram: _socialUrl(
          s.telegram,
          'Telegram',
          't.me',
          r'(?:t|telegram)\.me',
          r'[A-Za-z0-9_]{5,32}',
        ),
        instagram: _socialUrl(
          s.instagram,
          'Instagram',
          'instagram.com',
          r'instagram\.com',
          r'[A-Za-z0-9._]{1,30}',
        ),
      );

  static String _socialUrl(
    String raw,
    String label,
    String host,
    String hostPattern,
    String name,
  ) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final m = RegExp(
      '^(?:https?://)?(?:www\\.)?$hostPattern/($name)/?(?:\\?.*)?\$|^@?($name)\$',
    ).firstMatch(v);
    if (m == null) throw ApiException('$label: проверьте ссылку или @имя');
    return 'https://$host/${m.group(1) ?? m.group(2)}';
  }

  double _minOrder = 5000;
  @override
  Future<double> wholesaleMinOrder() async => _minOrder;
  @override
  Future<double> saveWholesaleMinOrder(double value) async => _minOrder = value;

  late final List<B2BCompany> _companies = [
    B2BCompany(
      id: 2,
      legalName: 'ИП Соколова Е. А.',
      taxId: '771234567859',
      status: B2BStatus.pending,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      members: const [
        B2BMember(id: 41, name: 'Елена Соколова', phone: '+79162223344'),
      ],
    ),
    B2BCompany(
      id: 1,
      legalName: 'ООО «Зелёная ложка»',
      taxId: '7704123450',
      status: B2BStatus.approved,
      createdAt: DateTime.now().subtract(const Duration(days: 12)),
      members: const [
        B2BMember(id: 40, name: 'Алексей Кравцов', phone: '+79161112233'),
      ],
    ),
  ];

  @override
  Future<List<B2BCompany>> companies() async => List.of(_companies);

  @override
  Future<void> decideCompany(
    int id, {
    required bool approve,
    String? note,
  }) async {
    final i = _companies.indexWhere((c) => c.id == id);
    _companies[i] = _companies[i].decided(approve: approve, note: note);
  }

  @override
  Future<void> createStaff({
    required String email,
    required String name,
    required String role,
    required String password,
  }) async => _staff.add(
    StaffMember(
      id: _staff.fold(0, (m, x) => max(m, x.id)) + 1,
      email: email,
      name: name,
      role: role,
    ),
  );
}
