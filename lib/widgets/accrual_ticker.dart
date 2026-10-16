import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/time_session_providers.dart';
import '../theme/glass_theme.dart';
import '../utils/currency_formatter.dart';
import 'glass_components.dart';

class AccrualTicker extends ConsumerWidget {
  final String employeeId;

  const AccrualTicker({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accrued = ref.watch(accruedWagesProvider(employeeId));
    final hoursWorked = ref.watch(hoursWorkedProvider(employeeId));
    final openSession = ref.watch(openSessionProvider(employeeId));
    final isClockedIn = openSession.valueOrNull != null;

    return GlassCard(
      radius: 20,
      surfaceColor: const Color(0x1A4A9EFF),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Earned this cycle',
                style: TextStyle(
                  color: context.onSurface(0.65),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              if (isClockedIn)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: glassSuccess.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: glassSuccess.withOpacity(0.40), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: glassSuccess,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          color: glassSuccess,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            CurrencyFormatter.format(accrued),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: context.onSurface(),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.schedule_outlined,
                  size: 14, color: context.onSurface(0.55)),
              const SizedBox(width: 4),
              Text(
                '${_formatHours(hoursWorked)} logged this cycle',
                style: TextStyle(
                    color: context.onSurface(0.55), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatHours(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
