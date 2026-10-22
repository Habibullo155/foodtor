import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode.dart';
import '../../../core/widgets/app_image.dart';
import '../../catalog/presentation/providers/catalog_filter.dart';
import '../../catalog/presentation/providers/shop_providers.dart';
import '../../catalog/presentation/widgets/price_tag.dart';
import '../../loyalty/presentation/loyalty_status_card.dart';
import '../account.dart';
import '../customer_session.dart';
import '../data/account_api.dart';
import 'address_form.dart';
import 'auth_sheet.dart';
import 'order_details.dart';

enum ProfileSection {
  profile('Профиль', Icons.person_outline_rounded),
  orders('Мои заказы', Icons.receipt_long_outlined),
  purchases('История покупок', Icons.history_rounded),
  addresses('Мои адреса', Icons.place_outlined),
  settings('Настройки', Icons.settings_outlined);

  const ProfileSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  ProfileSection _section = ProfileSection.orders;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(customerSessionProvider);
    return switch (session) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncData(value: final me?) => LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 900 ? _wide(me) : _narrow(me),
      ),
      _ => ListView(
        padding: const EdgeInsets.symmetric(vertical: Insets.xl),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 480),
              child: AuthForm(
                reason: 'Заказы, адреса, история покупок и персональные цены — в одном месте',
              ),
            ),
          ),
        ],
      ),
    };
  }

  Widget _wide(Me me) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 300,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.xl,
            0,
            Insets.xl,
          ),
          children: [
            _MeHeader(me: me),
            const SizedBox(height: Insets.lg),
            Container(
              padding: const EdgeInsets.all(Insets.sm),
              decoration: BoxDecoration(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: context.palette.border),
              ),
              child: Column(
                children: [
                  for (final s in ProfileSection.values)
                    _MenuItem(
                      section: s,
                      selected: s == _section,
                      onTap: () => setState(() => _section = s),
                    ),
                  const Divider(),
                  const _LogoutTile(),
                ],
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey(_section),
            child: _sectionBody(_section),
          ),
        ),
      ),
    ],
  );

  Widget _narrow(Me me) => ListView(
    padding: const EdgeInsets.all(Insets.lg),
    children: [
      _MeHeader(me: me),
      const SizedBox(height: Insets.lg),
      // Material, а не Container с цветом: иначе ripple у ListTile не виден
      Material(
        color: context.palette.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: context.palette.border),
        ),
        child: Column(
          children: [
            for (final (i, s) in ProfileSection.values.indexed) ...[
              if (i > 0) const Divider(indent: 56),
              ListTile(
                leading: Icon(s.icon),
                title: Text(s.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(s.label)),
                      body: _sectionBody(s),
                    ),
                  ),
                ),
              ),
            ],
            const Divider(indent: 56),
            const _LogoutTile(),
          ],
        ),
      ),
    ],
  );

  Widget _sectionBody(ProfileSection s) => switch (s) {
    ProfileSection.profile => const _ProfileSection(),
    ProfileSection.orders => const _OrdersSection(),
    ProfileSection.purchases => const _PurchasesSection(),
    ProfileSection.addresses => const _AddressesSection(),
    ProfileSection.settings => const _SettingsSection(signedIn: true),
  };
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });
  final ProfileSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? AppColors.brand.withValues(alpha: 0.1)
        : Colors.transparent,
    borderRadius: BorderRadius.circular(Radii.md),
    child: InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: 12,
        ),
        child: Row(
          children: [
            Icon(
              section.icon,
              size: 20,
              color: selected ? AppColors.brand : context.palette.textSecondary,
            ),
            const SizedBox(width: Insets.md),
            Flexible(
              child: Text(
                section.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.brand : null,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.me, this.radius = 28});
  final Me me;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: AppColors.brand,
    foregroundImage: me.avatarUrl == null
        ? null
        : AppImage.provider(me.avatarUrl!),
    child: Text(
      me.initials,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.6,
      ),
    ),
  );
}

class _MeHeader extends StatelessWidget {
  const _MeHeader({required this.me});
  final Me me;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Avatar(me: me),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                me.fullName,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                me.login,
                style: text.bodySmall?.copyWith(
                  color: context.palette.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (me.account.isVerifiedB2B)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: WholesaleBadge(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionScaffold extends StatelessWidget {
  const _SectionScaffold({
    required this.title,
    required this.children,
    this.action,
  });
  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: const EdgeInsets.all(Insets.xl),
      children: [
        if (wide || action != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.lg),
            child: Row(
              children: [
                if (wide)
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  )
                else
                  const Spacer(),
                ?action,
              ],
            ),
          ),
        ...children,
      ],
    );
  }
}

class _ProfileSection extends ConsumerStatefulWidget {
  const _ProfileSection();

  @override
  ConsumerState<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends ConsumerState<_ProfileSection> {
  final _form = GlobalKey<FormState>();
  late final Me _me = ref.read(customerSessionProvider).value!;
  late final _name = TextEditingController(text: _me.fullName);
  late final _phone = TextEditingController(text: _me.phone);
  bool _busy = false, _photoBusy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(customerSessionProvider.notifier)
          .updateProfile(
            name: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    final f = files.singleOrNull;
    if (f == null) return;
    setState(() => _photoBusy = true);
    try {
      await ref
          .read(customerSessionProvider.notifier)
          .uploadAvatar(await f.readAsBytes(), f.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(customerSessionProvider).value ?? _me;
    final loyalty = ref.watch(myLoyaltyProvider);
    return _SectionScaffold(
      title: 'Профиль',
      children: [
        Row(
          children: [
            Stack(
              children: [
                Avatar(me: me, radius: 48),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filled(
                    tooltip: 'Изменить фото',
                    onPressed: _photoBusy ? null : _pickPhoto,
                    icon: _photoBusy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(width: Insets.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    me.fullName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    me.login,
                    style: TextStyle(color: context.palette.textSecondary),
                  ),
                  const SizedBox(height: Insets.sm),
                  Wrap(
                    spacing: Insets.sm,
                    children: [
                      TextButton(
                        onPressed: _photoBusy ? null : _pickPhoto,
                        child: const Text('Загрузить фото'),
                      ),
                      if (me.avatarUrl != null)
                        TextButton(
                          onPressed: () => ref
                              .read(customerSessionProvider.notifier)
                              .deleteAvatar(),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.lowStock,
                          ),
                          child: const Text('Удалить'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.xl),
        if (loyalty case AsyncData(value: final data?)) ...[
          LoyaltyStatusCard(data: LoyaltyProgress.fromJson(data)),
          const SizedBox(height: Insets.xl),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Имя и фамилия',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().length < 2 ? 'Укажите имя' : null,
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Телефон',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ||
                          RegExp(r'^\+?[0-9 ()\-]{7,20}$').hasMatch(v!.trim())
                      ? null
                      : 'Проверьте телефон',
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  initialValue: me.login,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: me.email == null
                        ? 'Телефон (вход по SMS)'
                        : 'Email (логин)',
                    prefixIcon: Icon(
                      me.email == null
                          ? Icons.phone_iphone_rounded
                          : Icons.alternate_email,
                    ),
                  ),
                ),
                const SizedBox(height: Insets.xl),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Сохранить изменения'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OrdersFilter extends Notifier<bool> {
  @override
  bool build() => false; // false — все, true — только активные
  void set(bool v) => state = v;
}

final _activeOnlyProvider = NotifierProvider<_OrdersFilter, bool>(
  _OrdersFilter.new,
);

class _OrdersSection extends ConsumerWidget {
  const _OrdersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider);
    final activeOnly = ref.watch(_activeOnlyProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myOrdersProvider),
      child: _SectionScaffold(
        title: 'Мои заказы',
        action: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Все')),
            ButtonSegment(value: true, label: Text('Активные')),
          ],
          selected: {activeOnly},
          onSelectionChanged: (s) =>
              ref.read(_activeOnlyProvider.notifier).set(s.first),
        ),
        children: switch (orders) {
          AsyncData(:final value) => [
            for (final o in value.where(
              (o) => !activeOnly || !o.state.isClosed,
            ))
              _OrderCard(order: o),
            if (value.where((o) => !activeOnly || !o.state.isClosed).isEmpty)
              _Empty(
                icon: Icons.receipt_long_outlined,
                title: activeOnly ? 'Активных заказов нет' : 'Заказов пока нет',
                subtitle: 'Здесь будут ваши заказы и их статусы',
              ),
          ],
          AsyncError(:final error) => [
            Text('$error', style: const TextStyle(color: AppColors.lowStock)),
          ],
          _ => [
            const Center(
              child: Padding(
                padding: EdgeInsets.all(Insets.xl),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
        },
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});
  final CustomerOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Material(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.lg),
          onTap: () async {
            await showOrderDetails(context, order);
            ref.invalidate(myOrdersProvider);
          },
          child: Container(
            padding: const EdgeInsets.all(Insets.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: context.palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Заказ ${order.number}',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    OrderStateChip(order.state),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('d MMMM, HH:mm', 'ru').format(order.createdAt)} · ${order.itemsCount} шт. · ${order.paymentLabel}',
                  style: text.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
                const SizedBox(height: Insets.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: Insets.sm,
                        runSpacing: Insets.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final url in order.preview)
                            Container(
                              width: 44,
                              height: 44,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: context.palette.surfaceMuted,
                                borderRadius: BorderRadius.circular(Radii.sm),
                              ),
                              child: AppImage(
                                imageUrl: url,
                                fit: BoxFit.contain,
                                memCacheWidth: 100,
                              ),
                            ),
                          if (order.lines.length > 4)
                            Text(
                              '+${order.lines.length - 4}',
                              style: TextStyle(
                                color: context.palette.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Text(
                      rub.format(order.total),
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 16,
                      color: context.palette.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        order.state.isClosed
                            ? 'Подробнее и переписка'
                            : 'Подробнее · написать по заказу',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (order.state == OrderState.delivered)
                      TextButton.icon(
                        onPressed: () => repeatOrder(context, ref, order),
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text('Повторить'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PurchasesSection extends ConsumerWidget {
  const _PurchasesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(myPurchasesProvider);
    final products = {for (final p in ref.watch(allProductsProvider)) p.id: p};
    return _SectionScaffold(
      title: 'История покупок',
      children: switch (purchases) {
        AsyncData(:final value) when value.isEmpty => [
          const _Empty(
            icon: Icons.history_rounded,
            title: 'Покупок пока нет',
            subtitle: 'После доставки заказа товары появятся здесь — их можно будет купить снова в один тап',
          ),
        ],
        AsyncData(:final value) => [
          Text(
            'Всё, что вы покупали, — по дате последней покупки',
            style: TextStyle(color: context.palette.textSecondary),
          ),
          const SizedBox(height: Insets.md),
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
              final w = (c.maxWidth - Insets.md * (cols - 1)) / cols;
              return Wrap(
                spacing: Insets.md,
                runSpacing: Insets.md,
                children: [
                  for (final p in value)
                    SizedBox(
                      width: w,
                      child: _PurchaseTile(
                        purchase: p,
                        available: products[p.productId],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        AsyncError(:final error) => [
          Text('$error', style: const TextStyle(color: AppColors.lowStock)),
        ],
        _ => [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(Insets.xl),
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      },
    );
  }
}

class _PurchaseTile extends ConsumerWidget {
  const _PurchaseTile({required this.purchase, required this.available});
  final Purchase purchase;
  final dynamic available; // Product? — живой товар каталога (для корзины)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canBuy = available != null && purchase.inStock;
    final inCart = canBuy && ref.watch(cartQtyProvider(purchase.productId)) > 0;
    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: context.palette.surfaceMuted,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: purchase.imageUrl == null
                ? null
                : AppImage(
                    imageUrl: purchase.imageUrl!,
                    fit: BoxFit.contain,
                    memCacheWidth: 120,
                  ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  purchase.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Покупали ${purchase.timesBought} ${_times(purchase.timesBought)} · ${DateFormat('d MMM', 'ru').format(purchase.lastBoughtAt)}',
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  purchase.price == null
                      ? 'Нет в продаже'
                      : [
                          rub.format(purchase.price),
                          ?purchase.unit,
                        ].join(' · '),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: purchase.price == null
                        ? context.palette.textSecondary
                        : null,
                  ),
                ),
              ],
            ),
          ),
          if (inCart)
            const Icon(Icons.check_circle_rounded, color: AppColors.fresh)
          else
            IconButton.filledTonal(
              tooltip: canBuy ? 'В корзину' : 'Нет в наличии',
              onPressed: canBuy
                  ? () => ref.read(cartProvider.notifier).add(available)
                  : null,
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  static String _times(int n) =>
      (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20))
      ? 'раза'
      : 'раз';
}

class _AddressesSection extends ConsumerWidget {
  const _AddressesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressesProvider);
    return _SectionScaffold(
      title: 'Мои адреса',
      action: FilledButton.icon(
        onPressed: () => showAddressForm(context),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Добавить адрес'),
      ),
      children: switch (addresses) {
        AsyncData(:final value) when value.isEmpty => [
          const _Empty(
            icon: Icons.place_outlined,
            title: 'Адресов пока нет',
            subtitle: 'Сохраните адрес — он подставится при оформлении заказа',
          ),
        ],
        AsyncData(:final value) => [
          for (final a in value) _AddressCard(address: a),
        ],
        AsyncError(:final error) => [
          Text('$error', style: const TextStyle(color: AppColors.lowStock)),
        ],
        _ => [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(Insets.xl),
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      },
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.address});
  final Address address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = address;
    final icon = switch (a.label) {
      'Дом' => Icons.home_outlined,
      'Работа' => Icons.work_outline_rounded,
      'Дача' => Icons.cottage_outlined,
      _ => Icons.place_outlined,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: Insets.md),
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: a.isDefault ? AppColors.brand : context.palette.border,
          width: a.isDefault ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: a.isDefault
                ? AppColors.brand
                : context.palette.textSecondary,
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      a.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (a.isDefault) ...[
                      const SizedBox(width: Insets.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: const Text(
                          'Основной',
                          style: TextStyle(
                            color: AppColors.brand,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(a.oneLine),
                if (a.courierNote != null)
                  Text(
                    'Курьеру: ${a.courierNote}',
                    style: TextStyle(
                      color: context.palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            onSelected: (v) async {
              final n = ref.read(addressesProvider.notifier);
              switch (v) {
                case 'edit':
                  await showAddressForm(context, address: a);
                case 'default':
                  await n.save(a.withDefault(true));
                case 'delete':
                  await n.delete(a.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Изменить')),
              if (!a.isDefault)
                const PopupMenuItem(
                  value: 'default',
                  child: Text('Сделать основным'),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Удалить',
                  style: TextStyle(color: AppColors.lowStock),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends ConsumerWidget {
  const _SettingsSection({required this.signedIn});
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final account = ref.watch(accountProvider);
    return _SectionScaffold(
      title: 'Настройки',
      children: [
        Text(
          'Оформление',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Insets.sm),
        const ThemeModeSelector(),
        if (AppConfig.isDemo) ...[
          const SizedBox(height: Insets.xl),
          Text(
            'Демо: тип аккаунта',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Insets.sm),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'b2c', label: Text('Розница')),
              ButtonSegment(value: 'pending', label: Text('Опт (заявка)')),
              ButtonSegment(value: 'b2b', label: Text('Опт')),
            ],
            selected: {
              if (account.isVerifiedB2B)
                'b2b'
              else if (account.isPendingB2B)
                'pending'
              else
                'b2c',
            },
            onSelectionChanged: (s) =>
                ref.read(accountProvider.notifier).set(switch (s.first) {
                  'b2b' => const Account(
                    type: AccountType.b2b,
                    b2bStatus: B2BStatus.approved,
                    companyName: 'ООО «Партнёр»',
                  ),
                  'pending' => const Account(
                    type: AccountType.b2b,
                    b2bStatus: B2BStatus.pending,
                    companyName: 'ООО «Партнёр»',
                  ),
                  _ => const Account(type: AccountType.b2c),
                }),
          ),
          if (account.isPendingB2B)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Text(
                'Заявка на оптовый доступ на рассмотрении — до подтверждения действуют розничные цены.',
                style: TextStyle(color: context.palette.textSecondary),
              ),
            ),
        ],
        if (signedIn) ...[
          const SizedBox(height: Insets.xl),
          Text(
            'Безопасность',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Insets.sm),
          // У вошедших по SMS пароля нет — менять нечего
          if (ref.watch(customerSessionProvider).value?.email != null) ...[
            OutlinedButton.icon(
              onPressed: () => showChangePasswordDialog(context),
              icon: const Icon(Icons.password_rounded),
              label: const Text('Сменить пароль'),
            ),
            const SizedBox(height: Insets.sm),
          ],
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Выйти на всех устройствах?'),
                  content: const Text(
                    'Сессии на телефоне, планшете и других компьютерах завершатся. '
                    'Пригодится, если вы потеряли телефон или входили с чужого устройства.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Выйти везде'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await ref
                    .read(customerSessionProvider.notifier)
                    .logoutEverywhere();
              }
            },
            icon: const Icon(Icons.devices_other_rounded),
            label: const Text('Выйти на всех устройствах'),
          ),
          const SizedBox(height: Insets.sm),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.lowStock,
            ),
            onPressed: () =>
                ref.read(customerSessionProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Выйти из аккаунта'),
          ),
        ],
      ],
    );
  }
}

class _LogoutTile extends ConsumerWidget {
  const _LogoutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      leading: const Icon(Icons.logout_rounded, color: AppColors.lowStock),
      title: const Text(
        'Выйти',
        style: TextStyle(
          color: AppColors.lowStock,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () {
        Navigator.of(context).popUntil((r) => r.isFirst);
        ref.read(customerSessionProvider.notifier).logout();
      },
    ),
  );
}

Future<void> showChangePasswordDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ChangePasswordDialog(),
);

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _next, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(customerSessionProvider.notifier)
          .changePassword(_current.text, _next.text);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Пароль изменён. На других устройствах нужно войти заново.',
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(customerSessionProvider).value?.email;
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      suffixIcon: IconButton(
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(
          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    );
    return AlertDialog(
      title: const Text('Смена пароля'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _current,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: deco('Текущий пароль'),
                validator: (v) =>
                    (v ?? '').isEmpty ? 'Введите текущий пароль' : null,
              ),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _next,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
                decoration: deco('Новый пароль'),
                validator: (v) => passwordProblem(v ?? '', email: email),
              ),
              const SizedBox(height: 6),
              PasswordStrengthBar(_next.text, email: email),
              const SizedBox(height: Insets.md),
              TextFormField(
                controller: _repeat,
                obscureText: _obscure,
                decoration: deco('Повторите новый пароль'),
                validator: (v) =>
                    v != _next.text ? 'Пароли не совпадают' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: Insets.md),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.lowStock),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Сменить'),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Insets.xxl),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 34, color: AppColors.brand),
        ),
        const SizedBox(height: Insets.lg),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.textSecondary),
        ),
      ],
    ),
  );
}
