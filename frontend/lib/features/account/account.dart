import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AccountType { guest, b2c, b2b }

enum B2BStatus { pending, approved, rejected, suspended }

@immutable
class Account {
  const Account({required this.type, this.b2bStatus, this.companyName});

  static const guest = Account(type: AccountType.guest);

  final AccountType type;
  final B2BStatus? b2bStatus;
  final String? companyName;

  /// Только подтверждённый оптовик видит оптовые цены (бэкенд решает так же — это лишь для UI-бейджей).
  bool get isVerifiedB2B =>
      type == AccountType.b2b && b2bStatus == B2BStatus.approved;
  bool get isPendingB2B =>
      type == AccountType.b2b && b2bStatus == B2BStatus.pending;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    type: AccountType.values.byName(j['account_type'] as String),
    b2bStatus: switch (j['b2b']?['status']) {
      final String s => B2BStatus.values.byName(s),
      _ => null,
    },
    companyName: j['b2b']?['legal_name'] as String?,
  );
}

/// Тип аккаунта проверяется при старте и после логина (GET /me).
/// Все провайдеры с ценами делают ref.watch(accountProvider) — при логине, выходе
/// или одобрении B2B-заявки каталог и корзина автоматически перезапрашиваются с новыми ценами.
class AccountNotifier extends Notifier<Account> {
  @override
  Account build() => Account.guest;

  void set(Account account) => state = account;
}

final accountProvider = NotifierProvider<AccountNotifier, Account>(
  AccountNotifier.new,
);
