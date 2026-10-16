import 'package:flutter/material.dart';
import '../theme/glass_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/wage_calculator.dart';
import 'glass_components.dart';

/// "You receive E500, E525 will be deducted at payday" preview
/// (spec section 3) — shown before a worker submits a draw request.
class FeePreviewCard extends StatelessWidget {
  final double amount;
  final double feePercent;

  const FeePreviewCard({
    super.key,
    required this.amount,
    required this.feePercent,
  });

  @override
  Widget build(BuildContext context) {
    final fee = WageCalculator.feeFor(amount, feePercent);
    final total = WageCalculator.totalOwed(amount, feePercent);
    return GlassCard(
      radius: 14,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(context, 'You receive', CurrencyFormatter.format(amount)),
          _row(
              context,
              'Service fee (${(feePercent * 100).toStringAsFixed(0)}%)',
              CurrencyFormatter.format(fee)),
          Divider(color: context.surfaceTint(0.09)),
          _row(context, 'Deducted at payday',
              CurrencyFormatter.format(total),
              emphasize: true),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool emphasize = false}) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
