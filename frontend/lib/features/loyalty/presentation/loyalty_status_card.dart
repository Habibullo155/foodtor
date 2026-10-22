import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LoyaltyProgress {
  const LoyaltyProgress({
    required this.tierName,
    required this.tierColor,
    required this.discountLabel,
    required this.totalSpent,
    required this.progress,
    this.nextTierName,
    this.amountToNext,
  });

  final String tierName;
  final Color tierColor;
  final String discountLabel; // «5%» или «1 000 ₽»
  final double totalSpent;
  final double progress; // 0..1
  final String? nextTierName;
  final double? amountToNext;

  factory LoyaltyProgress.fromJson(Map<String, dynamic> j) {
    final cur = j['current_tier'] as Map<String, dynamic>?;
    final next = j['next_tier'] as Map<String, dynamic>?;
    final value = cur == null
        ? 0
        : double.parse(cur['discount_value'].toString());
    return LoyaltyProgress(
      tierName: cur?['name'] as String? ?? 'Новичок',
      tierColor: _hex(cur?['color_hex'] as String? ?? '#9E9E9E'),
      discountLabel: cur?['discount_type'] == 'fixed'
          ? _money.format(value)
          : '${value.toStringAsFixed(0)}%',
      totalSpent: double.parse(j['total_spent'].toString()),
      progress: (j['progress'] as num).toDouble(),
      nextTierName: next?['name'] as String?,
      amountToNext: j['amount_to_next'] == null
          ? null
          : double.parse(j['amount_to_next'].toString()),
    );
  }

  static Color _hex(String hex) =>
      Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
}

final _money = NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 0,
);

class LoyaltyStatusCard extends StatelessWidget {
  const LoyaltyStatusCard({super.key, required this.data});
  final LoyaltyProgress data;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const onTier = Colors.white;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            data.tierColor,
            Color.lerp(data.tierColor, Colors.black, 0.35)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: data.tierColor.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: onTier,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data.tierName,
                    style: text.headlineSmall?.copyWith(
                      color: onTier,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      'Скидка ${data.discountLabel}',
                      style: const TextStyle(
                        color: onTier,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Сумма покупок: ${_money.format(data.totalSpent)}',
              style: text.bodyMedium?.copyWith(color: onTier),
            ),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: data.progress),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation(onTier),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              data.nextTierName == null
                  ? 'Максимальный уровень достигнут 🎉'
                  : 'До уровня ${data.nextTierName} осталось ${_money.format(data.amountToNext)}',
              style: text.bodySmall?.copyWith(
                color: onTier.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
