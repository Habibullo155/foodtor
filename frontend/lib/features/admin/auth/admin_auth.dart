import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../rbac.dart';
import 'demo_accounts.dart';

/// Права ролей — зеркало backend DEFAULT_ROLE_PERMISSIONS.
const rolePermissions = <String, Set<Permission>>{
  'owner': {...Permission.values},
  'manager': {
    Permission.dashboardView,
    Permission.productsRead,
    Permission.productsWrite,
    Permission.productsImport,
    Permission.ordersReadAll,
    Permission.ordersUpdateStatus,
    Permission.reviewsModerate,
    Permission.b2bManage,
  },
  'picker': {Permission.ordersPick},
  'courier': {Permission.ordersDeliver},
};

const roleTitles = {
  'owner': 'Владелец',
  'manager': 'Менеджер',
  'picker': 'Сборщик заказов',
  'courier': 'Курьер',
};

@immutable
class AdminSession {
  const AdminSession({
    required this.email,
    required this.name,
    required this.role,
    this.grantedPermissions,
    this.title,
    this.phone,
  });
  final String email;
  final String name;
  final String role;
  final String? phone;
  final Set<Permission>?
  grantedPermissions; // из GET /auth/me (релиз); в демо — по роли
  final String? title;

  String get roleTitle => title ?? roleTitles[role] ?? role;
  Set<Permission> get permissions =>
      grantedPermissions ?? rolePermissions[role] ?? const {};
  String get initials => name
      .split(' ')
      .where((p) => p.isNotEmpty)
      .take(2)
      .map((p) => p[0])
      .join();
  String get firstName => name.split(' ').first;
}

sealed class LoginResult {
  const LoginResult();
}

class LoginOk extends LoginResult {
  const LoginOk();
}

class LoginFailed extends LoginResult {
  const LoginFailed(this.message);
  final String message;
}

/// Сессия админки. Демо-режим проверяет хэши локально; с бэкендом —
/// POST /api/v1/auth/login → access/refresh JWT в flutter_secure_storage, права из GET /me.
class AdminAuthNotifier extends Notifier<AdminSession?> {
  static const _maxAttempts = 5;
  static const _lockout = Duration(seconds: 30);

  int _failed = 0;
  DateTime? _lockedUntil;

  @override
  AdminSession? build() => null;

  /// Восстановление сессии сотрудника после перезагрузки страницы (релиз).
  Future<void> restore() async {
    if (AppConfig.isDemo || state != null) return;
    if (await restoreSession(ref)) await _loadMe();
  }

  Future<LoginResult> _loadMe() async {
    try {
      final me =
          (await ref
                  .read(dioProvider)
                  .get<Map<String, dynamic>>('/api/v1/auth/me'))
              .data!;
      if (me['is_staff'] != true) {
        await logoutSession(ref);
        return const LoginFailed(
          'Этот аккаунт не является сотрудником магазина',
        );
      }
      state = AdminSession(
        email: me['email'] as String,
        name: me['full_name'] as String,
        role: me['role'] as String,
        title: me['role_title'] as String?,
        phone: me['phone'] as String?,
        grantedPermissions: Permission.parse(
          (me['permissions'] as List).cast<String>(),
        ),
      );
      ref.read(permissionsProvider.notifier).set(state!.permissions);
      return const LoginOk();
    } catch (e) {
      return LoginFailed(ApiException.from(e).message);
    }
  }

  Future<LoginResult> login(String email, String password) async {
    if (!AppConfig.isDemo) {
      // Релиз: Argon2id + rate limit на сервере; ошибки — от API (без раскрытия, что неверно)
      try {
        await loginWithPassword(ref, email, password);
      } catch (e) {
        return LoginFailed(e.toString());
      }
      return _loadMe();
    }
    final now = DateTime.now();
    if (_lockedUntil case final until? when now.isBefore(until)) {
      return LoginFailed(
        'Слишком много попыток. Повторите через ${until.difference(now).inSeconds + 1} с',
      );
    }

    // Искусственная задержка: одинаковое время ответа для существующих и несуществующих логинов
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final account = demoAccounts
        .where((a) => a.email == email.trim().toLowerCase())
        .firstOrNull;
    final hash = sha256
        .convert(utf8.encode('${account?.salt ?? 'x'}$password'))
        .toString();
    if (account == null || hash != account.hash) {
      _failed++;
      if (_failed >= _maxAttempts) {
        _failed = 0;
        _lockedUntil = now.add(_lockout);
        return const LoginFailed(
          'Слишком много попыток. Вход заблокирован на 30 секунд',
        );
      }
      // Не раскрываем, что именно неверно — логин или пароль
      return LoginFailed(
        'Неверный email или пароль (осталось попыток: ${_maxAttempts - _failed})',
      );
    }

    _failed = 0;
    state = AdminSession(
      email: account.email,
      name: account.name,
      role: account.role,
    );
    ref.read(permissionsProvider.notifier).set(state!.permissions);
    return const LoginOk();
  }

  /// Имя и телефон поменяли в профиле — шапка и меню сразу показывают новые.
  void updateProfile({required String name, required String phone}) {
    final s = state;
    if (s == null) return;
    state = AdminSession(
      email: s.email,
      name: name,
      role: s.role,
      grantedPermissions: s.grantedPermissions,
      title: s.title,
      phone: phone,
    );
  }

  /// Тесты без DEMO_ACCOUNTS.md (CI): вход без пароля под демо-сотрудником.
  @visibleForTesting
  void signInForTest(AdminSession session) {
    state = session;
    ref.read(permissionsProvider.notifier).set(session.permissions);
  }

  void logout() {
    if (!AppConfig.isDemo) logoutSession(ref);
    state = null;
    ref.read(permissionsProvider.notifier).set(const {});
  }
}

final adminAuthProvider = NotifierProvider<AdminAuthNotifier, AdminSession?>(
  AdminAuthNotifier.new,
);

/// Старт админки: в релизе пробуем восстановить сессию по refresh-токену.
final adminBootstrapProvider = FutureProvider<void>(
  (ref) => ref.read(adminAuthProvider.notifier).restore(),
);
