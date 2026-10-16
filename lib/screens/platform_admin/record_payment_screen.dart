import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/settlement.dart';
import '../../providers/firebase_providers.dart';
import '../../services/platform_admin_service.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/glass_components.dart';

/// Platform-admin flow: record a payment seen on the bank statement against a
/// company's settlement reference. The platform admin never browses company
/// data; this form sends only what is on the statement line and shows only the
/// resulting status. The bank's transaction id makes it safe to submit the same
/// line twice (it is counted once).
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key});

  @override
  ConsumerState<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'SZL');
  final _txnCtrl = TextEditingController();

  bool _saving = false;
  String? _error;
  String? _result;

  @override
  void dispose() {
    for (final c in [_codeCtrl, _referenceCtrl, _amountCtrl, _currencyCtrl, _txnCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _result = null;
    });
    try {
      final payment = await ref.read(platformAdminServiceProvider).recordSettlementPayment(
            shortCode: _codeCtrl.text.trim().toUpperCase(),
            reference: _referenceCtrl.text.trim(),
            amountMinor: CurrencyFormatter.parseMinor(_amountCtrl.text)!,
            currency: _currencyCtrl.text.trim().toUpperCase(),
            providerTransactionId: _txnCtrl.text.trim(),
          );
      final status = SettlementStatus.fromCode(payment.status).label;
      setState(() {
        _result = '${payment.duplicate ? 'Already recorded, nothing changed. ' : 'Payment recorded. '}'
            'Total received ${CurrencyFormatter.formatMinor(payment.receivedMinor)}, '
            'outstanding ${CurrencyFormatter.formatMinor(payment.outstandingMinor)}. '
            'Status: $status.';
      });
      if (!payment.duplicate) {
        _amountCtrl.clear();
        _txnCtrl.clear();
      }
    } on CreateCompanyException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Record Payment')),
      body: GlassBackground(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Copy these from the bank statement line. Only record a payment '
                'you can see in the bank account, never one the employer only says it made.',
                style: TextStyle(fontSize: 12, color: context.onSurface(0.60)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeCtrl,
                decoration: const InputDecoration(labelText: 'Company code'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referenceCtrl,
                decoration: const InputDecoration(
                    labelText: 'Payment reference', hintText: 'EWA-ABC123-20261031-K3F9'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'Amount received', hintText: '1234.50'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final minor = CurrencyFormatter.parseMinor(v ?? '');
                  return (minor == null || minor <= 0) ? 'Enter an amount like 1234.50' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _currencyCtrl,
                decoration: const InputDecoration(labelText: 'Currency code'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _txnCtrl,
                decoration: const InputDecoration(
                    labelText: 'Bank transaction ID',
                    helperText: "The bank's own id for this line (letters, digits, - and _)"),
                validator: (v) => RegExp(r'^[A-Za-z0-9_-]{4,100}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : '4-100 letters, digits, dashes or underscores',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              if (_result != null) ...[
                const SizedBox(height: 16),
                Text(_result!, style: const TextStyle(color: Colors.green)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Record payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
