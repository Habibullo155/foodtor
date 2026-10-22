import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../customer_session.dart';
import '../data/account_api.dart';

/// Вход/регистрация покупателя в шторке. Возвращает true при успехе.
Future<bool> showAuthSheet(BuildContext context, {String? reason}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AuthForm(
        reason: reason,
        onDone: () => Navigator.of(context).pop(true),
      ),
    ),
  );
  return ok ?? false;
}

class AuthForm extends ConsumerStatefulWidget {
  const AuthForm({super.key, this.reason, this.onDone});
  final String? reason;
  final VoidCallback? onDone;

  @override
  ConsumerState<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<AuthForm> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _register = false;
  bool _byPhone = true; // по умолчанию — вход по номеру телефона (SMS)
  bool _withPassword =
      false; // email: по умолчанию код на почту, пароль — по ссылке
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _password, _name, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(customerSessionProvider.notifier);
    try {
      if (_register) {
        await session.register(
          email: _email.text,
          password: _password.text,
          name: _name.text,
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        );
      } else {
        await session.login(_email.text, _password.text);
      }
      widget.onDone?.call();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.xl),
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _byPhone
                    ? 'Вход и регистрация'
                    : (_register ? 'Регистрация' : 'Вход'),
                style: text.headlineSmall,
              ),
              if (widget.reason != null) ...[
                const SizedBox(height: Insets.xs),
                Text(
                  widget.reason!,
                  style: text.bodyMedium?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: Insets.lg),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.sms_outlined, size: 18),
                    label: Text('По телефону'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.alternate_email, size: 18),
                    label: Text('По email'),
                  ),
                ],
                selected: {_byPhone},
                onSelectionChanged: (s) => setState(() {
                  _byPhone = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: Insets.lg),
              if (_byPhone)
                CodeAuthFlow(
                  key: const ValueKey('sms'),
                  channel: CodeChannel.sms,
                  onDone: widget.onDone,
                )
              else if (!_withPassword) ...[
                CodeAuthFlow(
                  key: const ValueKey('email'),
                  channel: CodeChannel.email,
                  onDone: widget.onDone,
                ),
                const SizedBox(height: Insets.sm),
                TextButton(
                  onPressed: () => setState(() => _withPassword = true),
                  child: const Text('Войти по паролю'),
                ),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _withPassword = false),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Войти по коду из письма'),
                  ),
                ),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('Вход')),
                    ButtonSegment(value: true, label: Text('Регистрация')),
                  ],
                  selected: {_register},
                  onSelectionChanged: (s) => setState(() {
                    _register = s.first;
                    _error = null;
                  }),
                ),
                const SizedBox(height: Insets.lg),
                if (_register) ...[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
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
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(
                      labelText: 'Телефон (необязательно)',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: Insets.md),
                ],
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  validator: (v) =>
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch((v ?? '').trim())
                      ? null
                      : 'Проверьте email',
                ),
                const SizedBox(height: Insets.md),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: [
                    _register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    helperText: _register
                        ? 'Минимум 8 символов, буквы и цифры'
                        : null,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Показать пароль' : 'Скрыть пароль',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  onChanged: _register ? (_) => setState(() {}) : null,
                  validator: (v) {
                    final p = v ?? '';
                    if (!_register) return p.isEmpty ? 'Введите пароль' : null;
                    return passwordProblem(p, email: _email.text.trim());
                  },
                ),
                if (_register) ...[
                  const SizedBox(height: 6),
                  PasswordStrengthBar(
                    _password.text,
                    email: _email.text.trim(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: Insets.md),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.lowStock),
                  ),
                ],
                const SizedBox(height: Insets.xl),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(_register ? 'Создать аккаунт' : 'Войти'),
                ),
                if (AppConfig.isDemo && !_register) ...[
                  const SizedBox(height: Insets.md),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () async {
                      await ref
                          .read(customerSessionProvider.notifier)
                          .demoSignIn();
                      widget.onDone?.call();
                    },
                    icon: const Icon(Icons.person_pin_outlined),
                    label: const Text('Войти как демо-покупатель'),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    'Демо: можно и зарегистрироваться — аккаунт живёт до перезагрузки страницы. '
                    'После 5 неверных паролей вход блокируется, как на настоящем сайте.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar(this.password, {super.key, this.email});
  final String password;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final score = passwordScore(password, email: email);
    final (label, color) = switch (score) {
      0 => ('', context.palette.border),
      1 => ('Ненадёжный', AppColors.lowStock),
      2 => ('Нормальный', AppColors.hit),
      3 => ('Хороший', AppColors.fresh),
      _ => ('Отличный', AppColors.fresh),
    };
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: i < score ? color : context.palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 4),
        ],
        SizedBox(
          width: 90,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }
}

class CodeAuthFlow extends ConsumerStatefulWidget {
  const CodeAuthFlow({super.key, required this.channel, this.onDone});
  final CodeChannel channel;
  final VoidCallback? onDone;

  @override
  ConsumerState<CodeAuthFlow> createState() => _CodeAuthFlowState();
}

class _CodeAuthFlowState extends ConsumerState<CodeAuthFlow> {
  bool get _sms => widget.channel == CodeChannel.sms;
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  String? _sentTo; // нормализованный номер, на который ушёл код
  String? _devCode;
  String? _signupToken;
  String? _error;
  bool _busy = false;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_phone, _code, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  CustomerSessionNotifier get _session =>
      ref.read(customerSessionProvider.notifier);

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn--);
    });
  }

  Future<void> _send() => _run(() async {
    final sent = await _session.requestCode(widget.channel, _phone.text);
    setState(() {
      _sentTo = sent.target;
      _devCode = sent.devCode;
      _code.clear();
    });
    _startCountdown(sent.resendIn);
  });

  Future<void> _verify() => _run(() async {
    final r = await _session.verifyCode(widget.channel, _sentTo!, _code.text);
    if (r.needsName) {
      setState(() => _signupToken = r.signupToken);
    } else {
      widget.onDone?.call();
    }
  });

  Future<void> _complete() => _run(() async {
    if (_name.text.trim().length < 2) {
      throw 'Укажите имя';
    }
    await _session.completeSignup(widget.channel, _signupToken!, _name.text);
    widget.onDone?.call();
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    Widget primary(String label, VoidCallback? onPressed) => FilledButton(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: _busy ? null : onPressed,
      child: _busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Text(label),
    );

    final children = <Widget>[];
    if (_signupToken != null) {
      children.addAll([
        Text(
          '${_sms ? 'Номер' : 'Почта'} $_sentTo подтверждён${_sms ? '' : 'а'}. Как к вам обращаться?',
          style: text.bodyMedium,
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          onSubmitted: (_) => _complete(),
          decoration: const InputDecoration(
            labelText: 'Имя',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: Insets.lg),
        primary('Готово', _complete),
      ]);
    } else if (_sentTo == null) {
      children.addAll([
        TextField(
          controller: _phone,
          autofocus: true,
          keyboardType: _sms ? TextInputType.phone : TextInputType.emailAddress,
          autofillHints: [
            _sms ? AutofillHints.telephoneNumber : AutofillHints.email,
          ],
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            labelText: _sms ? 'Номер телефона' : 'Email',
            hintText: _sms ? '+7 9XX XXX-XX-XX' : 'name@mail.ru',
            prefixIcon: Icon(
              _sms ? Icons.phone_iphone_rounded : Icons.alternate_email,
            ),
          ),
        ),
        const SizedBox(height: Insets.sm),
        Text(
          _sms
              ? 'Пришлём SMS с кодом. Если номера ещё нет у нас — создадим аккаунт.'
              : 'Пришлём письмо с кодом. Если такой почты ещё нет у нас — создадим аккаунт.',
          style: text.bodySmall?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: Insets.lg),
        primary('Получить код', _send),
      ]);
    } else {
      children.addAll([
        Row(
          children: [
            Expanded(
              child: Text('Код отправлен на $_sentTo', style: text.bodyMedium),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _sentTo = null;
                      _error = null;
                    }),
              child: Text(_sms ? 'Изменить номер' : 'Изменить email'),
            ),
          ],
        ),
        if (_devCode != null)
          Container(
            margin: const EdgeInsets.only(top: Insets.xs),
            padding: const EdgeInsets.all(Insets.sm),
            decoration: BoxDecoration(
              color: AppColors.hit.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              AppConfig.isDemo
                  ? 'Демо: ${_sms ? 'SMS не отправляется' : 'письмо не отправляется'}, ваш код — $_devCode'
                  : 'Разработка: ${_sms ? 'SMS' : 'письмо'} не отправлено, код — $_devCode',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 8,
            fontWeight: FontWeight.w700,
          ),
          onChanged: (v) {
            if (v.length == 6 && !_busy) _verify();
          },
          onSubmitted: (_) => _verify(),
          decoration: InputDecoration(
            labelText: _sms ? 'Код из SMS' : 'Код из письма',
            counterText: '',
          ),
        ),
        const SizedBox(height: Insets.md),
        primary('Войти', _verify),
        const SizedBox(height: Insets.sm),
        TextButton(
          onPressed: _resendIn > 0 || _busy ? null : _send,
          child: Text(
            _resendIn > 0
                ? 'Отправить код ещё раз через $_resendIn с'
                : 'Отправить код ещё раз',
          ),
        ),
      ]);
    }
    if (_error != null) {
      children.addAll([
        const SizedBox(height: Insets.md),
        Text(_error!, style: const TextStyle(color: AppColors.lowStock)),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
