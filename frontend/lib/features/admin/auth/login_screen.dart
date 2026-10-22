import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_image.dart';
import '../../catalog/data/demo_catalog.dart';
import 'admin_auth.dart';
import '../../../core/theme/theme_mode.dart';

class AdminLoginScreen extends StatelessWidget {
  const AdminLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.surface,
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 960;
          final form = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Insets.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: const _LoginForm(),
              ),
            ),
          );
          final page = !wide
              ? SafeArea(child: form)
              : Row(
                  children: [
                    const Expanded(flex: 5, child: _BrandPanel()),
                    Expanded(flex: 4, child: form),
                  ],
                );
          return Stack(
            children: [
              page,
              const Positioned(
                top: Insets.lg,
                right: Insets.lg,
                child: SafeArea(child: ThemeModeButton()),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _floating = [
    'Strawberries',
    'Avocado',
    'Carrots',
    'Lemon',
    'Broccoli',
    'Coffee',
    'Honey',
    'Apple',
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E8A4C), AppColors.brand, Color(0xFF07432A)],
        ),
      ),
      padding: const EdgeInsets.all(48),
      child: Stack(
        children: [
          // Декоративная «витрина» из продуктов
          for (final (i, name) in _floating.indexed)
            Align(
              alignment: Alignment(
                -0.8 + (i % 4) * 0.55,
                -0.15 + (i ~/ 4) * 0.55 + (i.isEven ? 0.08 : -0.08),
              ),
              child: Container(
                width: 92,
                height: 92,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: AppImage(
                  imageUrl: ingredientImage(name),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BrandLogo(size: 40, onDark: true),
                  const SizedBox(width: Insets.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: const Text(
                      'Admin',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'Управляйте магазином\nв одном месте',
                style: text.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: Insets.lg),
              Text(
                'Заказы и сборка, каталог и остатки,\nфинансы и программа лояльности.',
                style: text.titleMedium?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoginForm extends ConsumerStatefulWidget {
  const _LoginForm();

  @override
  ConsumerState<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(adminAuthProvider.notifier)
        .login(_email.text, _password.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = switch (result) {
        LoginFailed(:final message) => message,
        LoginOk() => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Вход в админ-панель',
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Insets.sm),
            Text(
              'Используйте рабочую почту сотрудника',
              style: text.bodyMedium?.copyWith(
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: Insets.xxl),
            Text('Email', style: text.labelLarge),
            const SizedBox(height: Insets.sm),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'name@saasshop.local',
                prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
              ),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Введите корректный email'
                  : null,
            ),
            const SizedBox(height: Insets.lg),
            Text('Пароль', style: text.labelLarge),
            const SizedBox(height: Insets.sm),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '••••••••',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Показать пароль' : 'Скрыть пароль',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Введите пароль' : null,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _error == null
                  ? const SizedBox(height: Insets.xl)
                  : Container(
                      margin: const EdgeInsets.symmetric(vertical: Insets.lg),
                      padding: const EdgeInsets.all(Insets.md),
                      decoration: BoxDecoration(
                        color: AppColors.lowStock.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.lowStock,
                            size: 20,
                          ),
                          const SizedBox(width: Insets.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.lowStock),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Войти', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: Insets.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: context.palette.textSecondary,
                ),
                const SizedBox(width: 6),
                Text('Защищённое соединение · JWT', style: text.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
