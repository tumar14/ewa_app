import 'package:cloud_firestore/cloud_firestore.dart';

enum DrawStatus { pending, approved, rejected }

enum DisbursementStatus { pending, completed, failed }

class DrawRequest {
  final String id;
  final String employeeId;
  // Stored as integer cents (amountMinor/feeMinor/totalMinor); held here as
  // lilangeni for display only. The server does all limit and fee arithmetic.
  final double amount; // amount the worker receives
  final double fee;
  final double total; // amount deducted at payday (amount + fee)
  final DrawStatus status;
  final DateTime createdAt;
  final String? decidedBy;
  final DateTime? decidedAt;
  /// Set once a payroll run has deducted this draw from payout. Null means
  /// "still outstanding" — counts against the worker's per-cycle cap.
  final String? payrollRunId;
  final DisbursementStatus? disbursementStatus;
  final DateTime? disbursedAt;
  final String? disbursementRef;
  final String? reason;

  DrawRequest({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.fee,
    required this.total,
    required this.createdAt,
    this.status = DrawStatus.pending,
    this.decidedBy,
    this.decidedAt,
    this.payrollRunId,
    this.disbursementStatus,
    this.disbursedAt,
    this.disbursementRef,
    this.reason,
  });

  factory DrawRequest.fromMap(String id, Map<String, dynamic> map) {
    return DrawRequest(
      id: id,
      employeeId: map['employeeId'] as String,
      amount: (map['amountMinor'] as num).toInt() / 100,
      fee: (map['feeMinor'] as num).toInt() / 100,
      total: (map['totalMinor'] as num).toInt() / 100,
      status: DrawStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => DrawStatus.pending,
      ),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      decidedBy: map['decidedBy'] as String?,
      decidedAt: (map['decidedAt'] as Timestamp?)?.toDate(),
      payrollRunId: map['payrollRunId'] as String?,
      disbursementStatus: map['disbursementStatus'] == null
          ? null
          : DisbursementStatus.values.firstWhere(
              (e) => e.name == map['disbursementStatus'],
              orElse: () => DisbursementStatus.pending,
            ),
      disbursedAt: (map['disbursedAt'] as Timestamp?)?.toDate(),
      disbursementRef: map['disbursementRef'] as String?,
      reason: map['reason'] as String?,
    );
  }
}
