import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/draw_request.dart';
import '../models/settings.dart';
import '../providers/draw_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/time_session_providers.dart';
import '../theme/glass_theme.dart';
import '../utils/currency_formatter.dart';
import '../utils/pay_cycle.dart';
import '../utils/wage_calculator.dart';
import 'glass_components.dart';

class PayCycleCard extends ConsumerWidget {
  final String employeeId;
  const PayCycleCard({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final accrued  = ref.watch(accruedWagesProvider(employeeId));
    final draws    = ref.watch(outstandingDrawsProvider(employeeId)).valueOrNull ?? [];

    final now         = DateTime.now();
    final rule        = settings?.paydayRule ?? const PaydayRule();
    final cycleStart  = PayCycle.currentCycleStart(rule);
    final payday      = PayCycle.nextPayday(rule);
    final today       = DateTime(now.year, now.month, now.day);
    final daysToPayday = payday.difference(today).inDays;

    // Cycle progress bar: 0.0 → 1.0
    final totalCycleDays = payday.difference(cycleStart).inDays;
    final elapsedDays    = today.difference(cycleStart).inDays.clamp(0, totalCycleDays);
    final cycleProgress  = totalCycleDays > 0 ? elapsedDays / totalCycleDays : 0.0;

    final activeDraws     = draws.where((d) => d.status != DrawStatus.rejected).toList();
    final alreadyDrawn    = WageCalculator.alreadyDrawn(activeDraws);
    final totalFees       = activeDraws.fold<double>(0, (s, d) => s + d.fee);
    final deductedAtPayday = alreadyDrawn + totalFees;
    final estimatedNet    = (accrued - deductedAtPayday).clamp(0.0, double.infinity);
    final maxAdditional   = WageCalculator.maxAdditionalDraw(
      accrued:        accrued,
      maxDrawPercent: settings?.maxDrawPercent ?? 0.5,
      cycleDraws:     activeDraws,
    );

    final dateFmt   = DateFormat('d MMM');
    final paydayFmt = DateFormat('EEE, d MMM yyyy');

    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.all(0),
      showTopGloss: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: glassBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.calendar_month_outlined,
                      size: 16, color: glassBlue),
                ),
                const SizedBox(width: 10),
                Text('Pay cycle',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text(
                  '${dateFmt.format(cycleStart)} – ${dateFmt.format(payday)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // ── Cycle progress bar ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: cycleProgress,
                    minHeight: 5,
                    backgroundColor: context.surfaceTint(0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      daysToPayday <= 3 ? glassWarning : glassBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Day $elapsedDays of $totalCycleDays',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      '${(cycleProgress * 100).round()}% through',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Countdown + payday date ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: (daysToPayday <= 3 ? glassWarning : glassBlue)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (daysToPayday <= 3 ? glassWarning : glassBlue)
                      .withValues(alpha: 0.20),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // Large days number
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        daysToPayday == 0 ? '🎉' : '$daysToPayday',
                        style: TextStyle(
                          fontSize: daysToPayday == 0 ? 28 : 36,
                          fontWeight: FontWeight.w800,
                          color: daysToPayday <= 3 ? glassWarning : context.onSurface(),
                          height: 1.0,
                        ),
                      ),
                      if (daysToPayday > 0)
                        Text(
                          'day${daysToPayday == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.onSurface(0.55),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 1,
                    height: 40,
                    color: context.surfaceTint(0.10),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          daysToPayday == 0 ? 'Payday is today!' : 'Until payday',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          paydayFmt.format(payday),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pay breakdown ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                Divider(
                    color: context.surfaceTint(0.08), height: 1),
                const SizedBox(height: 14),
                _BreakdownRow(
                  label: 'Earned this cycle',
                  value: CurrencyFormatter.format(accrued),
                  bold: true,
                ),
                const SizedBox(height: 8),
                _BreakdownRow(
                  label: 'Advanced (principal)',
                  value: alreadyDrawn > 0
                      ? '− ${CurrencyFormatter.format(alreadyDrawn)}'
                      : '—',
                  valueColor: alreadyDrawn > 0 ? null : null,
                  dimmed: alreadyDrawn <= 0,
                ),
                const SizedBox(height: 8),
                _BreakdownRow(
                  label: 'Service fees',
                  value: totalFees > 0
                      ? '− ${CurrencyFormatter.format(totalFees)}'
                      : '—',
                  valueColor: totalFees > 0
                      ? glassDanger.withValues(alpha: 0.85)
                      : null,
                  dimmed: totalFees <= 0,
                ),
                const SizedBox(height: 12),
                Divider(
                    color: context.surfaceTint(0.08), height: 1),
                const SizedBox(height: 12),
                _BreakdownRow(
                  label: 'Estimated take-home',
                  value: CurrencyFormatter.format(estimatedNet),
                  valueColor: glassSuccess,
                  bold: true,
                  icon: Icons.account_balance_outlined,
                ),
              ],
            ),
          ),

          // ── Available-to-advance banner ────────────────────────────────
          if (maxAdditional > 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: glassSuccess.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: glassSuccess.withValues(alpha: 0.18), width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.savings_outlined,
                        size: 16, color: glassSuccess.withValues(alpha: 0.80)),
                    const SizedBox(width: 8),
                    Text(
                      'Available to advance: ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.onSurface(0.60),
                          ),
                    ),
                    Text(
                      CurrencyFormatter.format(maxAdditional),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: glassSuccess,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final bool dimmed;
  final IconData? icon;

  const _BreakdownRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
    this.dimmed = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: context.onSurface(0.60),
        );
    final resolvedColor = dimmed
        ? context.onSurface(0.30)
        : valueColor ?? context.onSurface();
    final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: resolvedColor,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        );
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: resolvedColor),
          const SizedBox(width: 6),
        ],
        Expanded(child: Text(label, style: labelStyle)),
        Text(value, style: valueStyle),
      ],
    );
  }
}
