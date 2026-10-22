import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';

/// Юридические страницы. Банк-эквайер (Альфа-Банк) проверяет их наличие перед подключением оплаты:
/// реквизиты продавца, оферта с условиями возврата, доставка/оплата, политика ПДн (152-ФЗ).
///
/// ⚠️ ШАБЛОНЫ. Значения в [квадратных скобках] нужно заменить на реальные реквизиты,
/// а тексты — согласовать с юристом до запуска.
abstract final class Seller {
  static const legalName = '[ООО «Название»]';
  static const inn = '[ИНН]';
  static const ogrn = '[ОГРН/ОГРНИП]';
  static const address = '[Юридический адрес]';
}

enum LegalDoc {
  offer('Публичная оферта', Icons.description_outlined),
  privacy('Политика конфиденциальности', Icons.privacy_tip_outlined),
  delivery('Доставка и оплата', Icons.local_shipping_outlined),
  returns('Возврат и обмен', Icons.assignment_return_outlined),
  contacts('Контакты и реквизиты', Icons.business_outlined);

  const LegalDoc(this.title, this.icon);
  final String title;
  final IconData icon;

  List<(String, String)> get sections => switch (this) {
    offer => [
      (
        '1. Общие положения',
        'Настоящий документ является публичной офертой ${Seller.legalName} (далее — Продавец) '
            'о продаже товаров дистанционным способом через сайт ${AppConfig.shopName}. '
            'Оформление заказа означает полное и безоговорочное принятие условий оферты (ст. 437, 438 ГК РФ).',
      ),
      (
        '2. Цены и оплата',
        'Цены указаны в рублях РФ с учётом НДС (если применимо). Цена фиксируется на момент оформления заказа. '
            'Оплата — банковской картой онлайн через платёжный шлюз АО «Альфа-Банк» или при получении.',
      ),
      (
        '3. Доставка',
        'Сроки и стоимость доставки указаны в разделе «Доставка и оплата» и при оформлении заказа.',
      ),
      (
        '4. Возврат',
        'Порядок возврата — в разделе «Возврат и обмен» в соответствии с Законом РФ «О защите прав потребителей».',
      ),
      (
        '5. Реквизиты продавца',
        '${Seller.legalName}, ИНН ${Seller.inn}, ${Seller.ogrn}, ${Seller.address}.',
      ),
    ],
    privacy => [
      (
        '1. Какие данные мы обрабатываем',
        'Имя, телефон, email, адрес доставки, история заказов — только для выполнения заказов и поддержки.',
      ),
      (
        '2. Цели и основания',
        'Исполнение договора купли-продажи (п. 5 ч. 1 ст. 6 152-ФЗ). Рассылки — только с отдельного согласия.',
      ),
      (
        '3. Передача третьим лицам',
        'Курьерской службе — для доставки; банку — для оплаты. Данные банковских карт обрабатывает только банк, '
            'на наших серверах они не хранятся.',
      ),
      (
        '4. Хранение и защита',
        'Данные хранятся на серверах в РФ, доступ ограничен, пароли хранятся в виде криптографических хэшей.',
      ),
      (
        '5. Ваши права',
        'Вы можете запросить, исправить или удалить свои данные, написав на ${AppConfig.supportEmail}.',
      ),
    ],
    delivery => [
      (
        'Экспресс-доставка',
        'За 2 часа, ${AppConfig.expressFee.toStringAsFixed(0)} ₽.',
      ),
      (
        'Курьер',
        'Сегодня или завтра в выбранный интервал. Бесплатно от ${AppConfig.freeCourierFrom.toStringAsFixed(0)} ₽, '
            'иначе ${AppConfig.courierFee.toStringAsFixed(0)} ₽.',
      ),
      ('Самовывоз', 'Бесплатно, заказ готов через 1 час.'),
      (
        'Способы оплаты',
        'Банковские карты Visa, Mastercard, МИР и СБП — онлайн; наличные или карта курьеру — при получении.',
      ),
      (
        'Безопасность платежей',
        'Оплата проходит на защищённой странице Альфа-Банка с технологией 3-D Secure. Магазин не получает и не хранит данные карт.',
      ),
    ],
    returns => [
      (
        'Товары надлежащего качества',
        'Свежие продукты питания надлежащего качества возврату не подлежат (Постановление Правительства РФ № 2463). '
            'Бакалею в ненарушенной упаковке можно вернуть в течение 7 дней.',
      ),
      (
        'Товары ненадлежащего качества',
        'Если продукт испорчен или не соответствует заказу — сообщите курьеру при получении или напишите нам в течение 24 часов, '
            'мы вернём деньги или заменим товар.',
      ),
      (
        'Возврат денег',
        'На ту же карту в течение 10 дней (обычно 1–3 дня), за наличные — переводом.',
      ),
    ],
    contacts => [
      (
        'Служба поддержки',
        'Телефон: ${AppConfig.supportPhone}\nEmail: ${AppConfig.supportEmail}\nЕжедневно с 8:00 до 22:00',
      ),
      (
        'Продавец',
        '${Seller.legalName}\nИНН ${Seller.inn}\n${Seller.ogrn}\n${Seller.address}',
      ),
    ],
  };
}

class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.doc});
  final LegalDoc doc;

  static Route<void> route(LegalDoc d) =>
      MaterialPageRoute(builder: (_) => LegalPage(doc: d));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(doc.title)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(Insets.xl),
            children: [
              for (final (title, body) in doc.sections) ...[
                Text(
                  title,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Insets.sm),
                Text(body, style: text.bodyLarge?.copyWith(height: 1.5)),
                const SizedBox(height: Insets.xl),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Insets.sm,
    runSpacing: Insets.xs,
    children: [
      for (final d in LegalDoc.values)
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(LegalPage.route(d)),
          icon: Icon(d.icon, size: 16),
          label: Text(d.title),
          style: TextButton.styleFrom(
            foregroundColor: context.palette.textSecondary,
          ),
        ),
    ],
  );
}

class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: context.palette.textSecondary,
      height: 1.5,
    );
    return Container(
      margin: const EdgeInsets.only(top: Insets.xxl),
      padding: const EdgeInsets.all(Insets.xl),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppConfig.shopName,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            '${AppConfig.supportPhone} · ${AppConfig.supportEmail} · ежедневно 8:00–22:00',
            style: muted,
          ),
          const SizedBox(height: Insets.md),
          const LegalLinks(compact: true),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (final p in ['Visa', 'Mastercard', 'МИР', 'СБП'])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.palette.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    p,
                    style: text.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Text(
            '© ${DateTime.now().year} ${Seller.legalName}, ИНН ${Seller.inn}, ${Seller.ogrn}',
            style: muted,
          ),
        ],
      ),
    );
  }
}
