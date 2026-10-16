import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/audit_log_entry.dart';
import '../../providers/audit_log_providers.dart';
import '../../providers/employee_providers.dart';
import '../../widgets/glass_components.dart';

/// Full audit trail (spec section 4/10): every draw decision, disbursement,
/// and employee change, with timestamp and approver identity. Read-only —
/// entries are written exclusively by Cloud Functions.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(auditLogProvider);
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(title: const Text('Audit Log')),
        body: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) {
            if (list.isEmpty) return const Center(child: Text('No audit entries yet.'));
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => _AuditTile(entry: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _AuditTile extends ConsumerWidget {
  final AuditLogEntry entry;

  const _AuditTile({required this.entry});

  IconData get _icon => switch (entry.type) {
        'employee_created' => Icons.person_add_outlined,
        'employee_deactivated' => Icons.person_off_outlined,
        'draw_decision' => Icons.fact_check_outlined,
        'disbursement' => Icons.send_to_mobile_outlined,
        'draw_request' => Icons.request_quote_outlined,
        'payroll_run' => Icons.payments_outlined,
        'settlement_created' ||
        'settlement_deductions_confirmed' ||
        'settlement_payment_recorded' ||
        'settlement_exception_resolved' ||
        'settlement_cancelled' =>
          Icons.account_balance_outlined,
        _ => Icons.history,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = entry.actorId == null
        ? null
        : ref.watch(employeeByIdProvider(entry.actorId!)).valueOrNull;
    final ts = entry.timestamp;
    final tsLabel = ts == null
        ? ''
        : '${ts.toLocal().year}-${ts.toLocal().month.toString().padLeft(2, '0')}-'
            '${ts.toLocal().day.toString().padLeft(2, '0')} '
            '${ts.toLocal().hour.toString().padLeft(2, '0')}:'
            '${ts.toLocal().minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: GlassCard(
        radius: 12,
        showTopGloss: false,
        child: ListTile(
          leading: Icon(_icon),
          title: Text(entry.summary),
          subtitle: Text(
            [
              if (tsLabel.isNotEmpty) tsLabel,
              if (actor != null) 'by ${actor.name}',
            ].join(' · '),
          ),
        ),
      ),
    );
  }
}
