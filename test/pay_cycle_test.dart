import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/models/settings.dart';
import 'package:ewa_app/utils/pay_cycle.dart';

// The same cases are checked against the server's port in
// functions/src/drawRules.test.ts, so the app and the Cloud Functions agree on
// where a pay cycle starts.
void main() {
  const lastDay = PaydayRule(type: PaydayType.lastDayOfMonth);
  const fixed25 = PaydayRule(type: PaydayType.fixedDayOfMonth, dayOfMonth: 25);
  const fixed31 = PaydayRule(type: PaydayType.fixedDayOfMonth, dayOfMonth: 31);
  const lastFriday = PaydayRule(type: PaydayType.lastWeekdayOfMonth, weekday: 5);

  group('PayCycle.currentCycleStart', () {
    test('last day of month: mid-cycle starts on the 1st', () {
      expect(PayCycle.currentCycleStart(lastDay, DateTime(2026, 10, 15)), DateTime(2026, 10, 1));
    });

    test('payday itself still belongs to the closing cycle', () {
      expect(PayCycle.currentCycleStart(lastDay, DateTime(2026, 10, 31)), DateTime(2026, 10, 1));
    });

    test('the day after payday starts a new cycle', () {
      expect(PayCycle.currentCycleStart(lastDay, DateTime(2026, 11, 1)), DateTime(2026, 11, 1));
    });

    test('January looks back to December of the previous year', () {
      expect(PayCycle.currentCycleStart(lastDay, DateTime(2026, 1, 10)), DateTime(2026, 1, 1));
    });

    test('fixed day of month', () {
      expect(PayCycle.currentCycleStart(fixed25, DateTime(2026, 10, 15)), DateTime(2026, 9, 26));
      expect(PayCycle.currentCycleStart(fixed25, DateTime(2026, 10, 26)), DateTime(2026, 10, 26));
    });

    test('fixed day 31 clamps to the end of a short month', () {
      expect(PayCycle.currentCycleStart(fixed31, DateTime(2026, 3, 5)), DateTime(2026, 3, 1));
    });

    test('last Friday of the month', () {
      // Sep 2026: the last Friday is the 25th, so the cycle starts on the 26th.
      expect(PayCycle.currentCycleStart(lastFriday, DateTime(2026, 10, 15)), DateTime(2026, 9, 26));
    });

    test('time of day is ignored', () {
      expect(PayCycle.currentCycleStart(lastDay, DateTime(2026, 10, 15, 14, 37, 55)),
          DateTime(2026, 10, 1));
    });
  });

  group('PayCycle.nextPayday', () {
    test('returns this month\'s payday while it is still ahead', () {
      expect(PayCycle.nextPayday(lastDay, DateTime(2026, 10, 15)), DateTime(2026, 10, 31));
      expect(PayCycle.nextPayday(lastDay, DateTime(2026, 10, 31)), DateTime(2026, 10, 31));
    });

    test('rolls to next month once payday has passed, including over a year end', () {
      expect(PayCycle.nextPayday(fixed25, DateTime(2026, 10, 26)), DateTime(2026, 11, 25));
      expect(PayCycle.nextPayday(lastDay, DateTime(2026, 12, 31)), DateTime(2026, 12, 31));
      expect(PayCycle.nextPayday(fixed25, DateTime(2026, 12, 26)), DateTime(2027, 1, 25));
    });
  });
}
