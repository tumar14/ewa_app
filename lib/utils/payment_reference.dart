/// Mirrors validatePaymentReference in functions/src/controls.ts; the server decides.
String? paymentReferenceProblem(String raw) {
  final ref = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._\-/]{3,59}$').hasMatch(ref)) {
    return 'Use 4 to 60 characters: letters, numbers and . _ - / only.';
  }
  if (RegExp(r'^DISP-', caseSensitive: false).hasMatch(ref)) {
    return 'Enter the reference from the bank or mobile-money payment, not an app-generated one.';
  }
  return null;
}
