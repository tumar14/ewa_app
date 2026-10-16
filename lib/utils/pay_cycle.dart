import '../models/settings.dart';

/// Pay-cycle boundary math. All logic is pure and testable — no I/O.
///
/// A pay cycle runs from the day after the previous payday up to and
/// including the next payday. The [PaydayRule] stored in [AppSettings]
/// controls which day of the month counts as payday.
class PayCycle {
  /// Returns the payday date for [year]/[month] under the given [rule].
  static DateTime paydayFor(int year, int month, PaydayRule rule) {
    switch (rule.type) {
      case PaydayType.fixedDayOfMonth:
        // Clamp to the actual last day so e.g. "31" works in February.
        final lastDay = DateTime(year, month + 1, 0).day;
        return DateTime(year, month, rule.dayOfMonth.clamp(1, lastDay));

      case PaydayType.lastDayOfMonth:
        // DateTime month+1, day 0 == last day of month.
        return DateTime(year, month + 1, 0);

      case PaydayType.lastWeekdayOfMonth:
        // Walk backwards from the last day until we hit the target weekday.
        var date = DateTime(year, month + 1, 0);
        while (date.weekday != rule.weekday) {
          date = date.subtract(const Duration(days: 1));
        }
        return date;
    }
  }

  /// The first day of the current pay cycle (the day after the most recent
  /// payday). Returns midnight-local for the result date.
  static DateTime currentCycleStart(PaydayRule rule, [DateTime? now]) {
    final today = now ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final thisPayday = paydayFor(today.year, today.month, rule);

    if (!todayDate.isAfter(thisPayday)) {
      // Payday is still in the future this month — cycle started after
      // last month's payday.
      final prevYear  = today.month == 1 ? today.year - 1 : today.year;
      final prevMonth = today.month == 1 ? 12 : today.month - 1;
      return paydayFor(prevYear, prevMonth, rule).add(const Duration(days: 1));
    }

    // This month's payday has passed — cycle started the day after it.
    return thisPayday.add(const Duration(days: 1));
  }

  /// The next payday on or after today.
  static DateTime nextPayday(PaydayRule rule, [DateTime? now]) {
    final today = now ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final thisPayday = paydayFor(today.year, today.month, rule);

    if (!todayDate.isAfter(thisPayday)) return thisPayday;

    final nextYear  = today.month == 12 ? today.year + 1 : today.year;
    final nextMonth = today.month == 12 ? 1 : today.month + 1;
    return paydayFor(nextYear, nextMonth, rule);
  }
}
