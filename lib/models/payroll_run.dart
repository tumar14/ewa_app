import 'package:cloud_firestore/cloud_firestore.dart';

/// One employee's line in a payroll run. Stored as integer cents (the
/// *Minor fields); held as lilangeni here for display only.
class EmployeePayrollLine {
  final String employeeId;
  final double accruedTotal;
  final double drawsDeducted;
  final double netPayout;

  /// Draws this cycle's wages could not cover. Net payout is never negative;
  /// the uncovered amount is reported here and raised as a settlement exception.
  final double shortfall;

  EmployeePayrollLine({
    required this.employeeId,
    required this.accruedTotal,
    required this.drawsDeducted,
    required this.netPayout,
    this.shortfall = 0,
  });

  factory EmployeePayrollLine.fromMap(Map<String, dynamic> map) {
    double money(String key) => ((map[key] as num?) ?? 0).toInt() / 100;
    return EmployeePayrollLine(
      employeeId: map['employeeId'] as String,
      accruedTotal: money('accruedMinor'),
      drawsDeducted: money('drawsDeductedMinor'),
      netPayout: money('netPayoutMinor'),
      shortfall: money('shortfallMinor'),
    );
  }
}

class PayrollRun {
  final String id;
  final DateTime cycleStart;
  final DateTime cycleEnd;
  final List<EmployeePayrollLine> lines;

  /// "applying" while draws are still being marked (an interrupted run is
  /// finished by running payroll again); "completed" once done.
  final String status;

  PayrollRun({
    required this.id,
    required this.cycleStart,
    required this.cycleEnd,
    required this.lines,
    this.status = 'completed',
  });

  bool get isCompleted => status == 'completed';

  factory PayrollRun.fromMap(String id, Map<String, dynamic> map) {
    return PayrollRun(
      id: id,
      cycleStart: (map['cycleStart'] as Timestamp).toDate(),
      cycleEnd: (map['cycleEnd'] as Timestamp).toDate(),
      status: map['status'] as String? ?? 'completed',
      lines: (map['lines'] as List<dynamic>? ?? [])
          .map((e) => EmployeePayrollLine.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
