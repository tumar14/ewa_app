import '../models/draw_request.dart';

/// Pure wage-accrual and draw-eligibility math. No Firebase, no I/O —
/// keep this unit-testable and the single source of truth for the
/// rules in spec sections 2-3.
class WageCalculator {
  /// hourly_rate * hours_worked, per section 2.
  static double accruedWages({
    required double hourlyRate,
    required Duration hoursWorked,
  }) {
    return hourlyRate * (hoursWorked.inMinutes / 60.0);
  }

  /// Sum of amounts (not totals) from prior draws already taken this cycle.
  static double alreadyDrawn(List<DrawRequest> cycleDraws) {
    return cycleDraws
        .where((d) => d.status != DrawStatus.rejected)
        .fold(0.0, (sum, d) => sum + d.amount);
  }

  /// Max additional amount a worker can request right now, given what
  /// they've already drawn this cycle.
  static double maxAdditionalDraw({
    required double accrued,
    required double maxDrawPercent,
    required List<DrawRequest> cycleDraws,
  }) {
    final cap = accrued * maxDrawPercent;
    final used = alreadyDrawn(cycleDraws);
    final remaining = cap - used;
    return remaining < 0 ? 0 : remaining;
  }

  static bool canRequestDraw({
    required List<DrawRequest> cycleDraws,
    required int maxDrawsPerCycle,
  }) {
    final nonRejected =
        cycleDraws.where((d) => d.status != DrawStatus.rejected).length;
    return nonRejected < maxDrawsPerCycle;
  }

  /// Fee charged on a draw, fixed at request time (section 3: no
  /// late/compounding fees — repayment is automatic via payroll deduction).
  static double feeFor(double amount, double feePercent) => amount * feePercent;

  /// Total deducted at next payday: amount received + fee.
  static double totalOwed(double amount, double feePercent) =>
      amount + feeFor(amount, feePercent);
}
