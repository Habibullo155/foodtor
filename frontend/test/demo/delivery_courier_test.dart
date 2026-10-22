import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saasshop/core/delivery/delivery_check.dart';
import 'package:saasshop/features/account/customer_session.dart';
import 'package:saasshop/features/admin/data/admin_data.dart';
import 'package:saasshop/features/admin/data/admin_repository.dart';
import 'package:saasshop/features/admin/rbac.dart';

import 'admin_test.dart' show login, pumpAdmin;
import 'profile_test.dart' show pumpProfile;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  setUp(() {
    DemoDeliveryChecker.radiusKm = 20;
    DemoDeliveryChecker.cities = const ['Москва'];
    DemoDeliveryChecker.enabled = true;
  });

  test('demo checker: radius, cities list, out-of-zone message', () async {
    final c = DemoDeliveryChecker();
    expect((await c.check('Москва, ул. Тверская, 1')).ok, isTrue);
    final tula = await c.check('Тула, ул. Ленина, 1');
    expect(tula.ok, isFalse);
    expect(tula.reason, contains('не доставляем'));
    DemoDeliveryChecker.cities = const ['Москва', 'Тула'];
    expect((await c.check('г. Тула, ул. Ленина, 1')).city, 'Тула');
    DemoDeliveryChecker.radiusKm = 10;
    expect((await c.check('Химки, Ленинский пр-т, 1')).ok, isFalse);
  });

  test(
    'address must have street and house: "Москва" alone is rejected',
    () async {
      final c = DemoDeliveryChecker();
      for (final bad in [
        'Москва',
        'Москва, 5',
        'Тверская',
        'Москва, Тверская улица',
      ]) {
        final v = await c.check(bad);
        expect(v.ok, isFalse, reason: bad);
        expect(v.needsDetails, isTrue, reason: bad);
      }
      expect(addressProblem('Москва, ул. Тверская, 12к2'), isNull);
      expect(addressProblem('Ленинский пр-т, 39/1'), isNull);
      expect((await c.check('Москва, Тверская, 1')).ok, isTrue);
    },
  );

  testWidgets('staff: owner deletes a picker (not himself)', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 1000));
    await login(tester, c, 'owner@saasshop.local');
    await tester.tap(find.text('Сотрудники').first);
    await settle(tester);
    expect(
      find.byTooltip('Удалить сотрудника'),
      findsNWidgets(c.read(staffProvider).length - 1),
    ); // себя — нельзя
    final before = c.read(staffProvider).length;
    await tester.tap(find.byTooltip('Удалить сотрудника').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await settle(tester);
    expect(c.read(staffProvider).length, before - 1);
    expect(find.textContaining('удалён(а) из сотрудников'), findsOneWidget);
  });

  testWidgets(
    'courier: take order, phone hidden until near, chat, emergency, delivered',
    (tester) async {
      final c = await pumpAdmin(tester, const Size(1440, 1000));
      await login(tester, c, 'courier@saasshop.local');
      expect(c.read(visibleSectionsProvider), [AdminSection.courier]);
      await settle(tester);
      expect(find.textContaining('Можно взять'), findsOneWidget);
      expect(find.textContaining('Везу сейчас'), findsOneWidget);
      expect(find.text('+7 ••• •••-••-18'), findsOneWidget); // номер скрыт

      final repo = c.read(adminRepositoryProvider) as DemoAdminRepository;
      final n = c.read(courierOrdersProvider.notifier);
      // едем к адресу: с каждой отправкой геопозиции ближе; в 1 км номер открывается
      for (
        var i = 0;
        i < 12 && c.read(courierOrdersProvider).first.phone == null;
        i++
      ) {
        final (lat, lng) = repo.demoNextPosition(9001);
        await tester.runAsync(() => n.locate(9001, lat, lng));
      }
      final o = c.read(courierOrdersProvider).firstWhere((x) => x.id == 9001);
      expect(o.phone, isNotNull);
      expect(o.distanceKm!, lessThanOrEqualTo(1));
      expect(o.phoneRevealReason, contains('рядом'));

      await tester.runAsync(() => n.take(9002));
      await tester.runAsync(
        () => n.emergency(9002, 'Покупатель не отвечает в чате'),
      );
      expect(
        c
            .read(courierOrdersProvider)
            .firstWhere((x) => x.id == 9002)
            .phoneRevealReason,
        startsWith('ЧП'),
      );
      final chat = await tester.runAsync(() => repo.courierChat(9002));
      expect(chat!.last.text, contains('открыл ваш номер'));

      await tester.runAsync(() => n.delivered(9001));
      expect(c.read(courierOrdersProvider).any((x) => x.id == 9001), isFalse);
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('picking: "Собрать всё" checks every line and enables handover', (
    tester,
  ) async {
    final c = await pumpAdmin(tester, const Size(1440, 1000));
    await login(tester, c, 'picker@saasshop.local');
    await settle(tester);
    final picking = c
        .read(adminOrdersProvider)
        .firstWhere((o) => o.stage == OrderStage.picking);
    expect(find.text('Собрать всё'), findsWidgets);
    await tester.tap(find.text('Собрать всё').first);
    await settle(tester);
    expect(
      c
          .read(adminOrdersProvider)
          .firstWhere((o) => o.id == picking.id)
          .pickedShare,
      1,
    );
    expect(find.text('Снять всё'), findsWidgets);
    expect(find.text('Собран — передать курьеру'), findsWidgets);
  });

  testWidgets('loyalty: owner edits and deletes a tier', (tester) async {
    final c = await pumpAdmin(tester, const Size(1440, 1000));
    await login(tester, c, 'owner@saasshop.local');
    final n = c.read(tiersProvider.notifier);
    final silver = c.read(tiersProvider).firstWhere((t) => t.name == 'Silver');
    await tester.runAsync(
      () => n.save(
        TierConfig(
          'Серебро',
          silver.threshold,
          4,
          silver.color,
          silver.customers,
          id: silver.id,
        ),
      ),
    );
    await settle(tester);
    expect(c.read(tiersProvider).map((t) => t.name), contains('Серебро'));
    expect(
      c.read(tiersProvider).firstWhere((t) => t.name == 'Серебро').percent,
      4,
    );
    await tester.runAsync(
      () => n.delete(
        c.read(tiersProvider).firstWhere((t) => t.name == 'Серебро'),
      ),
    );
    await settle(tester);
    expect(
      c.read(tiersProvider).map((t) => t.name),
      isNot(contains('Серебро')),
    );
  });

  testWidgets(
    'customer: logout shows login form; demo sign-in; register + lockout',
    (tester) async {
      final c = await pumpProfile(tester, const Size(1440, 1000));
      expect(find.text('Выйти'), findsOneWidget);
      await tester.tap(find.text('Выйти'));
      await settle(tester);
      expect(find.text('Вход и регистрация'), findsOneWidget);
      expect(find.text('По телефону'), findsOneWidget);
      expect(find.text('Получить код'), findsOneWidget);
      expect(
        find.text('Оформление'),
        findsNothing,
      ); // темы на странице входа нет
      expect(find.textContaining('оферты'), findsNothing);

      final s = c.read(customerSessionProvider.notifier);
      await tester.runAsync(
        () => s.register(
          email: 'ivan@test.ru',
          password: 'Ogurec-2026',
          name: 'Иван',
        ),
      );
      await settle(tester);
      expect(c.read(customerSessionProvider).value?.fullName, 'Иван');
      await tester.runAsync(s.logout);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => s.login('ivan@test.ru', 'wrong').catchError((_) {}),
        );
      }
      Object? err;
      await tester.runAsync(
        () => s.login('ivan@test.ru', 'Ogurec-2026').catchError((e) => err = e),
      );
      expect('$err', contains('Слишком много'));

      await tester.runAsync(s.demoSignIn);
      await settle(tester);
      expect(
        c.read(customerSessionProvider).value?.fullName,
        'Мария Кузнецова',
      );
    },
  );

  testWidgets(
    'owner sees: radius shortcut, product edit buttons, tier editor',
    (tester) async {
      final c = await pumpAdmin(tester, const Size(1440, 1000));
      await login(tester, c, 'owner@saasshop.local');
      await settle(tester);
      // дашборд → «Изменить радиус» ведёт в редактор зоны
      expect(find.text('Изменить радиус'), findsOneWidget);
      await tester.tap(find.text('Изменить радиус'));
      await settle(tester);
      expect(find.text('Радиус'), findsOneWidget);
      expect(find.text('Города, куда возим целиком'), findsOneWidget);

      await tester.tap(find.text('Товары').first);
      await settle(tester);
      expect(find.byTooltip('Изменить товар'), findsWidgets);
      await tester.tap(find.byTooltip('Изменить товар').first);
      await settle(tester);
      expect(find.text('Сохранить'), findsWidgets);
      expect(
        find.text('Заменить фото'),
        findsOneWidget,
      ); // загрузка с компьютера
      expect(find.textContaining('Лучше квадрат 1000×1000 px'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);

      await tester.tap(find.text('Лояльность').first);
      await settle(tester);
      expect(find.text('Уровни и пороги'), findsOneWidget);
      await tester.tap(find.text('Изменить').first);
      await settle(tester);
      expect(find.text('Сумма покупок от'), findsOneWidget);
      expect(find.text('Скидка'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone login: code → name for a new number; known number logs straight in',
    (tester) async {
      final c = await pumpProfile(tester, const Size(1440, 1000));
      await tester.tap(find.text('Выйти'));
      await settle(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Номер телефона'),
        '8 (926) 555-44-33',
      );
      await tester.tap(find.text('Получить код'));
      await settle(tester);
      expect(find.text('Код отправлен на +79265554433'), findsOneWidget);
      final hint = tester.widget<Text>(find.textContaining('ваш код —')).data!;
      final code = hint.split('— ').last;

      // 6-я цифра запускает проверку сама — нажимать «Войти» не нужно
      await tester.enterText(
        find.widgetWithText(TextField, 'Код из SMS'),
        '000000' == code ? '111111' : '000000',
      );
      await settle(tester);
      expect(
        find.textContaining('Неверный код. Осталось попыток: 4'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Код из SMS'),
        code,
      ); // 6 цифр — проверка сама
      await settle(tester);
      expect(find.textContaining('подтверждён'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Имя'), 'Ирина');
      await tester.tap(find.text('Готово'));
      await settle(tester);
      final me = c.read(customerSessionProvider).value!;
      expect(
        (me.fullName, me.email, me.login),
        ('Ирина', null, '+79265554433'),
      );

      // номер Марии уже есть в демо — входит сразу, без шага с именем
      final s = c.read(customerSessionProvider.notifier);
      await tester.runAsync(s.logout);
      final sent = (await tester.runAsync(
        () => s.requestPhoneCode('+7 916 123-45-67'),
      ))!;
      final r = (await tester.runAsync(
        () => s.verifyPhoneCode(sent.target, sent.devCode!),
      ))!;
      expect(r.needsName, isFalse);
      expect(
        c.read(customerSessionProvider).value?.fullName,
        'Мария Кузнецова',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'email code login: new email → name; password login still available',
    (tester) async {
      final c = await pumpProfile(tester, const Size(1440, 1000));
      await tester.tap(find.text('Выйти'));
      await settle(tester);
      await tester.tap(find.text('По email'));
      await settle(tester);
      expect(find.text('Войти по паролю'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'Olga@Mail.ru',
      );
      await tester.tap(find.text('Получить код'));
      await settle(tester);
      final code = tester
          .widget<Text>(find.textContaining('ваш код —'))
          .data!
          .split('— ')
          .last;
      await tester.enterText(
        find.widgetWithText(TextField, 'Код из письма'),
        code,
      );
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Имя'), 'Ольга');
      await tester.tap(find.text('Готово'));
      await settle(tester);
      final me = c.read(customerSessionProvider).value!;
      expect((me.fullName, me.email), ('Ольга', 'olga@mail.ru'));
    },
  );
}
