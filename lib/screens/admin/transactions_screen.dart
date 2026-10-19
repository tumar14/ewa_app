import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/draw_request.dart';
import '../../providers/draw_providers.dart';
import '../../providers/employee_providers.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/glass_components.dart';

enum _Filter { all, pending, approved, paid, rejected }

/// Every advance for this company, newest first: who asked, how much, the fee
/// and where it stands. Read-only; approvals and payments happen on their own
/// tabs.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  _Filter _filter = _Filter.all;

  static bool _isPaid(DrawRequest d) =>
      d.status == DrawStatus.approved && d.disbursementStatus == DisbursementStatus.completed;

  bool _matches(DrawRequest d) => switch (_filter) {
        _Filter.all => true,
        _Filter.pending => d.status == DrawStatus.pending,
        _Filter.approved => d.status == DrawStatus.approved && !_isPaid(d),
        _Filter.paid => _isPaid(d),
        _Filter.rejected => d.status == DrawStatus.rejected,
      };

  (String, Color) _status(DrawRequest d) {
    if (d.status == DrawStatus.rejected) return ('Declined', glassDanger);
    if (d.status == DrawStatus.pending) return ('Pending', glassWarning);
    if (_isPaid(d)) return ('Paid', glassSuccess);
    return ('Approved, to be paid', glassBlue);
  }

  void _copyCsv(List<DrawRequest> list) {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    final rows = <String>['date,employee,amount,fee,total,status,payment_ref'];
    for (final d in list) {
      final name = ref.read(employeeByIdProvider(d.employeeId)).valueOrNull?.name ?? d.employeeId;
      rows.add([
        q(d.createdAt.toLocal().toString().split('.').first),
        q(name),
        d.amount.toStringAsFixed(2),
        d.fee.toStringAsFixed(2),
        d.total.toStringAsFixed(2),
        q(_status(d).$1),
        q(d.disbursementRef ?? ''),
      ].join(','));
    }
    Clipboard.setData(ClipboardData(text: rows.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transactions copied. Paste them into a spreadsheet.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allDrawsProvider);
    final filtered = (all.valueOrNull ?? const <DrawRequest>[]).where(_matches).toList();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: 'Copy as CSV',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: filtered.isEmpty ? null : () => _copyCsv(filtered),
          ),
        ],
      ),
      body: GlassBackground(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (f) {
                          _Filter.all => 'All',
                          _Filter.pending => 'Pending',
                          _Filter.approved => 'To be paid',
                          _Filter.paid => 'Paid',
                          _Filter.rejected => 'Declined',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: all.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (_) {
                  if (filtered.isEmpty) {
                    return const Center(child: Text('No transactions to show.'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final d = filtered[i];
                      final name = ref.watch(employeeByIdProvider(d.employeeId)).valueOrNull?.name ??
                          d.employeeId;
                      final (label, color) = _status(d);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          radius: 14,
                          showTopGloss: false,
                          child: ListTile(
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${d.createdAt.toLocal().toString().split('.').first}\n'
                              'Fee ${CurrencyFormatter.format(d.fee)} · '
                              'Deducted at payroll ${CurrencyFormatter.format(d.total)}',
                            ),
                            isThreeLine: true,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(CurrencyFormatter.format(d.amount),
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                GlassChip(label: label, color: color),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
