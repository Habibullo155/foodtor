import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/customer_session.dart';
import '../../account/data/account_api.dart';

/// Банк возвращает покупателя на /#/payment?result=success|fail|error&order=ID.
/// Сам результат не проверяется по URL (его можно подделать) — сервер уже сверил статус с банком,
/// а здесь мы лишь показываем сообщение и обновляем список заказов.
({String result, int? orderId})? parsePaymentReturn(Uri uri) {
  final fragment = uri.fragment;
  if (!fragment.startsWith('/payment')) return null;
  final q = Uri.parse(fragment).queryParameters;
  return (
    result: q['result'] ?? 'error',
    orderId: int.tryParse(q['order'] ?? ''),
  );
}

Future<void> handlePaymentReturn(BuildContext context, WidgetRef ref) async {
  if (AppConfig.isDemo) return;
  final ret = parsePaymentReturn(Uri.base);
  if (ret == null) return;
  ref.invalidate(myOrdersProvider);
  final ok = ret.result == 'success';
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(
        ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
        color: ok ? AppColors.fresh : AppColors.lowStock,
        size: 56,
      ),
      title: Text(ok ? 'Оплата прошла' : 'Оплата не прошла'),
      content: Text(
        ok
            ? 'Спасибо! Мы уже собираем ваш заказ — статус можно отслеживать в профиле.'
            : 'Деньги не списаны. Можно попробовать ещё раз или выбрать оплату при получении.',
        textAlign: TextAlign.center,
      ),
      actions: [
        if (!ok && ret.orderId != null)
          FilledButton(
            onPressed: () async {
              try {
                final url = await ref
                    .read(accountApiProvider)
                    .payAgain(ret.orderId!);
                await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
              } catch (e) {
                if (c.mounted) {
                  ScaffoldMessenger.of(c)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('Оплатить снова'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(ok ? 'Отлично' : 'Закрыть'),
        ),
      ],
    ),
  );
}
