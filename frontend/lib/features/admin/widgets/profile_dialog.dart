import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../auth/admin_auth.dart';
import '../data/admin_data.dart';
import '../data/admin_repository.dart';

Future<void> showProfileDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ProfileDialog());

class _ProfileDialog extends ConsumerStatefulWidget {
  const _ProfileDialog();

  @override
  ConsumerState<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends ConsumerState<_ProfileDialog> {
  late final session = ref.read(adminAuthProvider)!;
  late final _name = TextEditingController(text: session.name);
  late final _phone = TextEditingController(text: session.phone ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final problem = name.length < 2
        ? 'Укажите имя'
        : phone.isNotEmpty && !RegExp(r'^\+?[0-9 ()\-]{7,20}$').hasMatch(phone)
        ? 'Телефон: только цифры, пробелы, скобки и дефис'
        : null;
    setState(() => _error = problem);
    if (problem != null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateMyProfile(name: name, phone: phone);
      ref
          .read(adminAuthProvider.notifier)
          .updateProfile(name: name, phone: phone);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ref.read(adminErrorProvider.notifier).report(e);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Мой профиль'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${session.email} · ${session.roleTitle}',
            style: TextStyle(color: context.palette.textSecondary),
          ),
          const SizedBox(height: Insets.lg),
          TextField(
            controller: _name,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Имя и фамилия',
              helperText:
                  'Видно покупателям в ответах поддержки и в чате заказа',
            ),
          ),
          const SizedBox(height: Insets.sm),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Телефон',
              hintText: '+7 (9XX) XXX-XX-XX',
            ),
          ),
          if (_error case final e?) ...[
            const SizedBox(height: Insets.md),
            Text(e, style: const TextStyle(color: AppColors.lowStock)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('Сохранить'),
      ),
    ],
  );
}
