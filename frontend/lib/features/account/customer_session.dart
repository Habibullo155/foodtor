import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import 'account.dart';
import 'data/account_api.dart';

/// Сессия покупателя. null — гость.
/// Релиз: восстанавливается по refresh-токену при старте. Демо: сразу «вошла» демо-покупательница.
class CustomerSessionNotifier extends AsyncNotifier<Me?> {
  AccountApi get _api => ref.read(accountApiProvider);

  @override
  Future<Me?> build() async {
    if (AppConfig.isDemo) return _apply(await _api.me());
    ref.listen(sessionExpiredProvider, (_, _) => _setGuest());
    if (!await restoreSession(ref)) return null;
    try {
      return _apply(await _api.me());
    } catch (_) {
      return null;
    }
  }

  Me _apply(Me me) {
    ref.read(accountProvider.notifier).set(me.account);
    return me;
  }

  void _setGuest() {
    ref.read(accountProvider.notifier).set(Account.guest);
    state = const AsyncData(null);
  }

  Future<void> login(String email, String password) async {
    await _api.login(email, password);
    state = AsyncData(_apply(await _api.me()));
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    await _api.register(
      email: email,
      password: password,
      name: name,
      phone: phone,
    );
    state = AsyncData(_apply(await _api.me()));
  }

  // Вход по коду: SMS на телефон или письмо на email
  Future<CodeSent> requestCode(CodeChannel channel, String target) =>
      _api.requestCode(channel, target);

  /// Вошли — или новый номер/email, нужно имя (затем [completeSignup]).
  Future<PhoneVerifyResult> verifyCode(
    CodeChannel channel,
    String target,
    String code,
  ) async {
    final r = await _api.verifyCode(channel, target, code);
    if (!r.needsName) state = AsyncData(_apply(await _api.me()));
    return r;
  }

  Future<void> completeSignup(
    CodeChannel channel,
    String signupToken,
    String name,
  ) async {
    await _api.completeSignup(channel, signupToken, name);
    state = AsyncData(_apply(await _api.me()));
  }

  // старые имена — для экранов/тестов входа по телефону
  Future<CodeSent> requestPhoneCode(String phone) =>
      requestCode(CodeChannel.sms, phone);
  Future<PhoneVerifyResult> verifyPhoneCode(String phone, String code) =>
      verifyCode(CodeChannel.sms, phone, code);

  /// Демо: вход без пароля под демо-покупательницей.
  Future<void> demoSignIn() async {
    if (_api case final DemoAccountApi demo) demo.useDemoCustomer();
    state = AsyncData(_apply(await _api.me()));
  }

  Future<void> changePassword(String current, String next) =>
      _api.changePassword(current, next);

  Future<void> logoutEverywhere() async {
    await _api.logoutAll();
    _setGuest();
  }

  Future<void> updateProfile({required String name, String? phone}) async {
    final me = state.value;
    if (me == null) return;
    state = AsyncData(await _api.updateProfile(me, name: name, phone: phone));
  }

  Future<void> uploadAvatar(List<int> bytes, String filename) async {
    final url = await _api.uploadAvatar(bytes, filename);
    state = AsyncData(state.value?.copyWith(avatarUrl: () => url));
  }

  Future<void> deleteAvatar() async {
    await _api.deleteAvatar();
    state = AsyncData(state.value?.copyWith(avatarUrl: () => null));
  }

  Future<void> logout() async {
    if (!AppConfig.isDemo) await logoutSession(ref);
    _setGuest();
  }
}

final customerSessionProvider =
    AsyncNotifierProvider<CustomerSessionNotifier, Me?>(
      CustomerSessionNotifier.new,
    );

final myOrdersProvider = FutureProvider.autoDispose<List<CustomerOrder>>((
  ref,
) async {
  final me = await ref.watch(customerSessionProvider.future);
  if (me == null) return const [];
  return ref.read(accountApiProvider).orders();
});

final myPurchasesProvider = FutureProvider.autoDispose<List<Purchase>>((
  ref,
) async {
  final me = await ref.watch(customerSessionProvider.future);
  if (me == null) return const [];
  return ref.read(accountApiProvider).purchases();
});

final myLoyaltyProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((
  ref,
) async {
  final me = await ref.watch(customerSessionProvider.future);
  if (me == null || me.account.type == AccountType.b2b) return null;
  return ref.read(accountApiProvider).loyalty();
});

class AddressesNotifier extends AsyncNotifier<List<Address>> {
  AccountApi get _api => ref.read(accountApiProvider);

  @override
  Future<List<Address>> build() async {
    final me = await ref.watch(customerSessionProvider.future);
    if (me == null) return const [];
    return _api.addresses();
  }

  Future<Address> save(Address a) async {
    final saved = await _api.saveAddress(a);
    state = AsyncData(await _api.addresses());
    return saved;
  }

  Future<void> delete(int id) async {
    await _api.deleteAddress(id);
    state = AsyncData(await _api.addresses());
  }
}

final addressesProvider =
    AsyncNotifierProvider<AddressesNotifier, List<Address>>(
      AddressesNotifier.new,
    );

final orderCommentsProvider = FutureProvider.autoDispose
    .family<List<OrderMessage>, int>(
      (ref, orderId) => ref.read(accountApiProvider).comments(orderId),
    );
