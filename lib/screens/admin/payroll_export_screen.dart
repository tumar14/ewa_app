import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/payroll_run.dart';
import '../../models/settlement.dart';
import '../../providers/payroll_providers.dart';
import '../../providers/employee_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/settlement_providers.dart';
import '../../services/settlement_repository.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/glass_components.dart';
import 'settlements_screen.dart';

/// Read-only export for Accounts to reconcile against actual payday
/// (spec section 9). "Run payroll" triggers the `runPayroll` Cloud
/// Function, which resets accrual and deducts outstanding draws. Each run
/// links to the employer settlement created from it.
class PayrollExportScreen extends ConsumerWidget {
  const PayrollExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(recentPayrollRunsProvider);
    final settlements = ref.watch(settlementsProvider).valueOrNull ?? const <Settlement>[];
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Payroll')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.play_arrow),
        label: const Text('Run payroll'),
        onPressed: () => _confirmAndRun(context, ref),
      ),
      body: GlassBackground(
        child: runs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) {
            if (list.isEmpty) return const Center(child: Text('No payroll runs yet.'));
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final run = list[i];
                final settlement =
                    settlements.where((s) => s.payrollRunId == run.id).firstOrNull;
                return _RunTile(run: run, settlement: settlement);
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmAndRun(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run payroll?'),
        content: const Text(
          'This resets accrued wages and deducts outstanding draws for '
          'every employee. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Run')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(payrollRepositoryProvider).triggerRun();
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not run payroll.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not run payroll. Check your connection.')),
        );
      }
    }
  }
}

class _RunTile extends ConsumerWidget {
  final PayrollRun run;
  final Settlement? settlement;

  const _RunTile({required this.run, required this.settlement});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalNet = run.lines.fold<double>(0, (sum, l) => sum + l.netPayout);
    final totalDrawn = run.lines.fold<double>(0, (sum, l) => sum + l.drawsDeducted);
    final totalShort = run.lines.fold<double>(0, (sum, l) => sum + l.shortfall);

    return ExpansionTile(
      title: Text(
        '${run.cycleStart.toLocal().toString().split(' ').first} - '
        '${run.cycleEnd.toLocal().toString().split(' ').first}',
      ),
      subtitle: Text(
        'Net payout ${CurrencyFormatter.format(totalNet)} · '
        'Draws deducted ${CurrencyFormatter.format(totalDrawn)}'
        '${totalShort > 0 ? ' · Not covered ${CurrencyFormatter.format(totalShort)}' : ''}',
      ),
      trailing: run.isCompleted ? null : const Chip(label: Text('Unfinished')),
      children: [
        ...run.lines.map((l) {
          final name =
              ref.watch(employeeByIdProvider(l.employeeId)).valueOrNull?.name ?? l.employeeId;
          return ListTile(
            title: Text(name),
            subtitle: Text(
              'Accrued ${CurrencyFormatter.format(l.accruedTotal)} · '
              'Drawn ${CurrencyFormatter.format(l.drawsDeducted)}'
              '${l.shortfall > 0 ? ' · Not covered ${CurrencyFormatter.format(l.shortfall)}' : ''}',
            ),
            trailing: Text(CurrencyFormatter.format(l.netPayout)),
          );
        }),
        if (!run.isCompleted)
          const ListTile(
            leading: Icon(Icons.warning_amber_outlined),
            title: Text('This run did not finish. Run payroll again to complete it.'),
          )
        else if (settlement != null)
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: Text('Settlement ${settlement!.reference}'),
            subtitle: Text(settlement!.status.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettlementDetailScreen(settlementId: settlement!.id))),
          )
        else if (totalDrawn > 0)
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('No settlement yet'),
            subtitle: const Text('Track what the employer remits for these deductions.'),
            trailing: FilledButton(
              onPressed: () => _createSettlement(context, ref),
              child: const Text('Create settlement'),
            ),
          ),
      ],
    );
  }

  Future<void> _createSettlement(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(settlementRepositoryProvider).createForRun(run.id);
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SettlementDetailScreen(settlementId: run.id)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(settlementErrorMessage(e))));
      }
    }
  }
}
