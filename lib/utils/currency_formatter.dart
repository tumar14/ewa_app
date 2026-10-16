import 'package:intl/intl.dart';

/// Formats amounts as Eswatini Lilangeni, e.g. "E 1,350.00".
///
/// Stored balances are integer cents ("minor units"); use [formatMinor] for
/// those and [parseMinor] to read what a person typed, so no money amount is
/// ever held as a floating-point number.
class CurrencyFormatter {
  static final _format = NumberFormat.currency(
    locale: 'en_SZ',
    symbol: 'E ',
    decimalDigits: 2,
  );

  static String format(double amount) => _format.format(amount);

  static String formatMinor(int minor) => _format.format(minor / 100);

  /// Whole cents for a lilangeni amount from a slider or similar.
  static int toMinor(double amount) => (amount * 100).round();

  /// Parses "1234", "1234.5" or "1234.50" into cents; null if it is not a
  /// plain non-negative amount with at most two decimals.
  static int? parseMinor(String input) {
    final match = RegExp(r'^(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch(input.trim());
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final fraction = int.parse((match.group(2) ?? '').padRight(2, '0'));
    return whole * 100 + fraction;
  }
}
