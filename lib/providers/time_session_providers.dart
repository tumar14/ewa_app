import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings.dart';
import '../models/time_session.dart';
import '../utils/attendance_rules.dart';
import '../utils/pay_cycle.dart';
import '../utils/wage_calculator.dart';
import 'firebase_providers.dart';
import 'employee_providers.dart';
import 'settings_providers.dart';

final openSessionProvider =
    StreamProvider.family<TimeSession?, String>((ref, employeeId) {
  return ref.watch(timeSessionRepositoryProvider).watchOpenSession(employeeId);
});

final cycleSessionsProvider =
    StreamProvider.family<List<TimeSession>, String>((ref, employeeId) {
  final rule = ref.watch(appSettingsProvider).valueOrNull?.paydayRule
      ?? const PaydayRule();
  return ref.watch(timeSessionRepositoryProvider).watchForEmployee(
        employeeId,
        cycleStart: PayCycle.currentCycleStart(rule),
      );
});

/// Every punch on a given day across all employees — supervisor daily
/// sign-off screen (spec section 6).
final sessionsForDayProvider =
    StreamProvider.family<List<TimeSession>, DateTime>((ref, day) {
  return ref.watch(timeSessionRepositoryProvider).watchForDay(day);
});

/// One employee's full punch history — Workforce screen drill-down.
final employeeSessionsProvider =
    StreamProvider.family<List<TimeSession>, String>((ref, employeeId) {
  return ref.watch(timeSessionRepositoryProvider).watchAllForEmployee(employeeId);
});

/// Count of flagged (unreviewed) punches today — drives the dashboard alert.
final flaggedTodayCountProvider = StreamProvider<int>((ref) {
  final today = DateTime.now();
  final day = DateTime(today.year, today.month, today.day);
  return ref
      .watch(timeSessionRepositoryProvider)
      .watchForDay(day)
      .map((sessions) => sessions.where((s) => s.flagged).length);
});

/// Ticks once a second so the accrual ticker below stays live while a
/// session is open, without re-subscribing to Firestore every tick.
final _tickerProvider = StreamProvider<int>((ref) {
  return Stream.periodic(const Duration(seconds: 1), (i) => i);
});

/// Total hours worked so far this pay cycle (spec section 9, worker home
/// "hours logged"). Ticks live alongside the accrual ticker while a
/// session is open.
final hoursWorkedProvider = Provider.family<Duration, String>((ref, employeeId) {
  ref.watch(_tickerProvider);
  final sessions = ref.watch(cycleSessionsProvider(employeeId)).valueOrNull ?? [];
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  // The same rules the server applies before time counts towards an advance:
  // voided records out, one record capped, overlaps merged, and (if the company
  // insists) only signed-off time.
  final countOnlyReviewed = settings?.countOnlyReviewedHours ?? false;
  final spans = sessions
      .where((s) => !s.voided && (!countOnlyReviewed || s.isReviewed))
      .map((s) => TimeSpan(s.clockIn, s.clockOut));
  return countableDuration(
    spans,
    DateTime.now(),
    maxShift: Duration(hours: settings?.maxShiftHours ?? kDefaultMaxShiftHours),
  );
});

/// Live accrued wages for the current pay cycle (spec section 2/9 "live
/// accrual ticker"). Recomputes every second from the latest known
/// session list + hourly rate — cheap, no extra Firestore reads.
final accruedWagesProvider = Provider.family<double, String>((ref, employeeId) {
  final employee = ref.watch(employeeByIdProvider(employeeId)).valueOrNull;
  final totalWorked = ref.watch(hoursWorkedProvider(employeeId));
  if (employee == null) return 0;
  return WageCalculator.accruedWages(
    hourlyRate: employee.hourlyRate,
    hoursWorked: totalWorked,
  );
});
