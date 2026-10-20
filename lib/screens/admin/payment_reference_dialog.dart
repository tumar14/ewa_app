import 'package:flutter/material.dart';
import '../../utils/payment_reference.dart';

/// Asks for the bank or mobile-money reference of a payment that has been made.
/// Returns it, or null if cancelled. The server checks it again and refuses one that is
/// already used, so a payment can be matched to a real transaction.
Future<String?> askPaymentReference(
  BuildContext context, {
  required String amountText,
  required String payee,
  required String method,
}) {
  final ctrl = TextEditingController();
  String? problem;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Record the payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pay $amountText to $payee first (bank transfer, mobile money or cash). Hola Manje '
              'records the payment; it does not send the money.\n\nPayment method on file: $method',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'Payment reference (required)',
                helperText: 'The transaction number from the bank or mobile-money receipt',
                errorText: problem,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final p = paymentReferenceProblem(ctrl.text);
              if (p != null) {
                setState(() => problem = p);
                return;
              }
              Navigator.pop(ctx, ctrl.text.trim().replaceAll(RegExp(r'\s+'), ' '));
            },
            child: const Text('Confirm payment'),
          ),
        ],
      ),
    ),
  ).whenComplete(ctrl.dispose);
}
