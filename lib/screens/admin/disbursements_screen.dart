import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'payment_reference_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/draw_request.dart';
import '../../providers/draw_providers.dart';
import '../../providers/employee_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/glass_components.dart';

/// Shows approved draws that are pending disbursement. The finance team
/// taps "Disburse" to confirm money has been sent (bank transfer, mobile
/// money, or cash). The `disburseDraw` Cloud Function marks it complete
/// and writes an audit log entry.
class DisbursementsScreen extends ConsumerWidget {
  const DisbursementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draws = ref.watch(approvedPendingDisbursementProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Disbursements')),
      body: draws.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Text('No approved draws awaiting disbursement.'),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) => _DisburseCard(draw: list[i]),
          );
        },
      ),
    );
  }
}

class _DisburseCard extends ConsumerStatefulWidget {
  final DrawRequest draw;

  const _DisburseCard({required this.draw});

  @override
  ConsumerState<_DisburseCard> createState() => _DisburseCardState();
}

class _DisburseCardState extends ConsumerState<_DisburseCard> {
  bool _loading = false;

  Future<void> _disburse() async {
    final employee = ref.read(employeeByIdProvider(widget.draw.employeeId)).valueOrNull;
    final reference = await askPaymentReference(
      context,
      amountText: 'E${widget.draw.amount.toStringAsFixed(2)}',
      payee: employee?.name ?? widget.draw.employeeId,
      method: employee?.disbursementMethod.name ?? '—',
    );
    if (reference == null) return;

    setState(() => _loading = true);
    try {
      await ref.read(drawRepositoryProvider).disburse(widget.draw.id, reference);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'The payment could not be recorded.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disbursement failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee =
        ref.watch(employeeByIdProvider(widget.draw.employeeId)).valueOrNull;

    final methodLabel = switch (employee?.disbursementMethod) {
      null => '—',
      _ => switch (employee!.disbursementMethod.name) {
          'bankTransfer' => 'Bank · ${employee.disbursementDetails['bankName'] ?? ''} '
              '${employee.disbursementDetails['accountNumber'] ?? ''}',
          'mobileMoney' => '${employee.disbursementDetails['provider'] ?? 'Mobile'} · '
              '${employee.disbursementDetails['phoneNumber'] ?? ''}',
          _ => 'Cash',
        },
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    employee?.name ?? widget.draw.employeeId,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  CurrencyFormatter.format(widget.draw.amount),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              methodLabel,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0x99FFFFFF)),
            ),
            Text(
              'Approved ${_formatDate(widget.draw.decidedAt ?? widget.draw.createdAt)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0x99FFFFFF)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_outlined),
                label: const Text('Mark as paid'),
                onPressed: _loading ? null : _disburse,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
