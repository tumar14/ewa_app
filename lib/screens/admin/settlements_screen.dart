import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/settlement.dart';
import '../../providers/employee_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/settlement_providers.dart';
import '../../services/settlement_repository.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/glass_components.dart';

Color _statusColor(SettlementStatus status) => switch (status) {
      SettlementStatus.settled => Colors.green,
      SettlementStatus.exception => Colors.redAccent,
      SettlementStatus.due => Colors.blue,
      SettlementStatus.partiallySettled => Colors.amber,
      SettlementStatus.draft || SettlementStatus.cancelled => Colors.grey,
    };

String _date(DateTime d) => d.toLocal().toString().split(' ').first;

/// What employers owe for the draws deducted in each payroll run, and whether
/// the money has arrived. Created from a payroll run (Payroll screen).
class SettlementsScreen extends ConsumerWidget {
  const SettlementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlements = ref.watch(settlementsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Settlements')),
      body: GlassBackground(
        child: settlements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No settlements yet. Open a payroll run and choose '
                  '"Create settlement" to start tracking it.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final s = list[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: GlassCard(
                  radius: 12,
                  showTopGloss: false,
                  child: ListTile(
                    title: Text(s.reference),
                    subtitle: Text(
                      '${_date(s.cycleStart)} - ${_date(s.cycleEnd)}\n'
                      'Expected ${CurrencyFormatter.formatMinor(s.expectedMinor)} · '
                      'Received ${CurrencyFormatter.formatMinor(s.receivedMinor)}',
                    ),
                    isThreeLine: true,
                    trailing: GlassChip(label: s.status.label, color: _statusColor(s.status)),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SettlementDetailScreen(settlementId: s.id))),
                  ),
                ),
              );
            },
          );
        },
        ),
      ),
    );
  }
}

class SettlementDetailScreen extends ConsumerWidget {
  final String settlementId;

  const SettlementDetailScreen({super.key, required this.settlementId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlementAsync = ref.watch(settlementProvider(settlementId));
    final items = ref.watch(settlementItemsProvider(settlementId)).valueOrNull ?? const [];
    final exceptions =
        ref.watch(settlementExceptionsProvider(settlementId)).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: const Text('Settlement'),
        actions: [
          IconButton(
            tooltip: 'Copy deduction list (CSV)',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => _copyCsv(context, ref, items),
          ),
        ],
      ),
      body: GlassBackground(
        child: settlementAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (s) {
            if (s == null) return const Center(child: Text('Settlement not found.'));
            final open = exceptions.where((e) => e.isOpen).toList();
            final closed = exceptions.where((e) => !e.isOpen).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeaderCard(settlement: s),
                const SizedBox(height: 12),
                _FiguresCard(settlement: s),
                const SizedBox(height: 12),
                if (!s.isCancelled) _Actions(settlement: s),
                if (open.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionTitle('Needs attention (${open.length})'),
                  ...open.map((e) => _ExceptionCard(settlementId: s.id, exception: e)),
                ],
                if (closed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const _SectionTitle('Resolved'),
                  ...closed.map((e) => _ExceptionCard(settlementId: s.id, exception: e)),
                ],
                const SizedBox(height: 16),
                _SectionTitle('Deductions by employee (${items.length})'),
                ...items.map((item) => _ItemTile(item: item)),
              ],
            );
          },
        ),
      ),
    );
  }

  void _copyCsv(BuildContext context, WidgetRef ref, List<SettlementItem> items) {
    final rows = <String>['employee_number,name,deduction'];
    for (final item in items) {
      final employee = ref.read(employeeByIdProvider(item.employeeId)).valueOrNull;
      final name = (employee?.name ?? item.employeeId).replaceAll('"', '""');
      final number = (employee?.employeeNumber ?? '').replaceAll('"', '""');
      rows.add('"$number","$name",${(item.drawsDeductedMinor / 100).toStringAsFixed(2)}');
    }
    Clipboard.setData(ClipboardData(text: rows.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deduction list copied. Paste it into a spreadsheet.')),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(fontWeight: FontWeight.w600, color: context.onSurface(0.80))),
      );
}

class _HeaderCard extends StatelessWidget {
  final Settlement settlement;
  const _HeaderCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SelectableText(s.reference,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              IconButton(
                tooltip: 'Copy payment reference',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: s.reference));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reference copied.')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Use this reference on the bank transfer so the payment can be matched.',
              style: TextStyle(fontSize: 12, color: context.onSurface(0.55))),
          const SizedBox(height: 10),
          Row(
            children: [
              GlassChip(label: s.status.label, color: _statusColor(s.status)),
              const SizedBox(width: 8),
              Text('${_date(s.cycleStart)} - ${_date(s.cycleEnd)}',
                  style: TextStyle(color: context.onSurface(0.60))),
            ],
          ),
          if (s.isCancelled && s.cancelledReason != null) ...[
            const SizedBox(height: 8),
            Text('Cancelled: ${s.cancelledReason}',
                style: TextStyle(color: context.onSurface(0.70))),
          ],
        ],
      ),
    );
  }
}

class _FiguresCard extends StatelessWidget {
  final Settlement settlement;
  const _FiguresCard({required this.settlement});

  Widget _row(BuildContext context, String label, String value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: context.onSurface(0.70)))),
          Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    final f = CurrencyFormatter.formatMinor;
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _row(context, 'Expected deductions', f(s.expectedMinor)),
          _row(context, 'Confirmed by payroll',
              s.confirmedMinor == null ? 'Not confirmed yet' : f(s.confirmedMinor!)),
          _row(context, 'Received', f(s.receivedMinor)),
          const Divider(),
          _row(context, 'Outstanding', f(s.outstandingMinor), bold: true),
        ],
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  final Settlement settlement;
  const _Actions({required this.settlement});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = settlement;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: Text(s.confirmedMinor == null ? 'Confirm payroll deductions' : 'Change confirmed amount'),
          onPressed: () => _confirmDeductions(context, ref),
        ),
        if (s.receivedMinor == 0)
          OutlinedButton.icon(
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancel settlement'),
            onPressed: () => _cancel(context, ref),
          ),
      ],
    );
  }

  Future<void> _confirmDeductions(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(
      text: settlement.confirmedMinor == null
          ? ''
          : (settlement.confirmedMinor! / 100).toStringAsFixed(2),
    );
    String? error;
    final minor = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Confirm payroll deductions'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Expected ${CurrencyFormatter.formatMinor(settlement.expectedMinor)}. '
                  'Enter the total payroll actually deducted for this cycle, from the payroll report.'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount deducted (E)',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final parsed = CurrencyFormatter.parseMinor(ctrl.text);
                if (parsed == null) {
                  setState(() => error = 'Enter an amount like 1234.50');
                  return;
                }
                Navigator.pop(ctx, parsed);
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (minor == null || !context.mounted) return;
    try {
      await ref.read(settlementRepositoryProvider).confirmDeductions(settlement.id, minor);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(settlementErrorMessage(e))));
      }
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await _askText(
      context,
      title: 'Cancel settlement',
      label: 'Reason',
      action: 'Cancel settlement',
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(settlementRepositoryProvider).cancel(settlement.id, reason);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(settlementErrorMessage(e))));
      }
    }
  }
}

class _ExceptionCard extends ConsumerWidget {
  final String settlementId;
  final SettlementException exception;

  const _ExceptionCard({required this.settlementId, required this.exception});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = exception;
    final f = CurrencyFormatter.formatMinor;
    final name = e.employeeId == null
        ? null
        : ref.watch(employeeByIdProvider(e.employeeId!)).valueOrNull?.name ?? e.employeeId;
    final diff = e.differenceMinor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        radius: 12,
        showTopGloss: false,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(e.isOpen ? Icons.error_outline : Icons.check_circle_outline,
                    size: 18, color: e.isOpen ? Colors.redAccent : Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (name != null) name,
                'Expected ${f(e.expectedMinor)}',
                'Actual ${f(e.actualMinor)}',
                'Difference ${diff < 0 ? '-' : '+'}${f(diff.abs())}',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: context.onSurface(0.65)),
            ),
            if (!e.isOpen && e.resolutionNote != null) ...[
              const SizedBox(height: 4),
              Text(e.resolutionNote!, style: TextStyle(fontSize: 12, color: context.onSurface(0.80))),
            ],
            if (e.isOpen)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _resolve(context, ref),
                  child: const Text('Resolve'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolve(BuildContext context, WidgetRef ref) async {
    final note = await _askText(
      context,
      title: 'Resolve: ${exception.title}',
      label: 'What was decided? (kept in the audit log)',
      action: 'Resolve',
    );
    if (note == null || !context.mounted) return;
    try {
      await ref
          .read(settlementRepositoryProvider)
          .resolveException(settlementId, exception.id, note);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(settlementErrorMessage(err))));
      }
    }
  }
}

class _ItemTile extends ConsumerWidget {
  final SettlementItem item;
  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(employeeByIdProvider(item.employeeId)).valueOrNull?.name ?? item.employeeId;
    final f = CurrencyFormatter.formatMinor;
    return ListTile(
      dense: true,
      title: Text(name),
      subtitle: item.shortfallMinor > 0
          ? Text('Pay covered ${f(item.accruedMinor)}; ${f(item.shortfallMinor)} not covered')
          : null,
      trailing: Text(f(item.drawsDeductedMinor)),
    );
  }
}

/// Asks for a short written note (5-500 characters, same limits the server enforces).
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
}) async {
  final ctrl = TextEditingController();
  String? error;
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(labelText: label, errorText: error),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          FilledButton(
            onPressed: () {
              final value = ctrl.text.trim();
              if (value.length < 5) {
                setState(() => error = 'Write at least 5 characters.');
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: Text(action),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return text;
}
