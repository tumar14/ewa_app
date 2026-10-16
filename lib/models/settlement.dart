import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of an employer settlement for one payroll run. The server
/// (functions/src/settlementRules.ts) is the only thing that sets it.
enum SettlementStatus {
  draft('DRAFT', 'Draft'),
  due('DUE', 'Due'),
  partiallySettled('PARTIALLY_SETTLED', 'Part paid'),
  settled('SETTLED', 'Settled'),
  exception('EXCEPTION', 'Needs attention'),
  cancelled('CANCELLED', 'Cancelled');

  final String code;
  final String label;
  const SettlementStatus(this.code, this.label);

  static SettlementStatus fromCode(String? code) => SettlementStatus.values
      .firstWhere((s) => s.code == code, orElse: () => SettlementStatus.draft);
}

/// All money here is integer cents; format with CurrencyFormatter.formatMinor.
class Settlement {
  final String id;
  final String payrollRunId;
  final String reference;
  final String currency;
  final SettlementStatus status;
  final DateTime cycleStart;
  final DateTime cycleEnd;
  final int expectedMinor;
  final int? confirmedMinor;
  final int receivedMinor;
  final int outstandingMinor;
  final int openExceptionCount;
  final int itemCount;
  final String? cancelledReason;

  Settlement({
    required this.id,
    required this.payrollRunId,
    required this.reference,
    required this.currency,
    required this.status,
    required this.cycleStart,
    required this.cycleEnd,
    required this.expectedMinor,
    required this.confirmedMinor,
    required this.receivedMinor,
    required this.outstandingMinor,
    required this.openExceptionCount,
    required this.itemCount,
    this.cancelledReason,
  });

  factory Settlement.fromMap(String id, Map<String, dynamic> map) {
    return Settlement(
      id: id,
      payrollRunId: map['payrollRunId'] as String? ?? id,
      reference: map['reference'] as String? ?? '',
      currency: map['currency'] as String? ?? 'SZL',
      status: SettlementStatus.fromCode(map['status'] as String?),
      cycleStart: (map['cycleStart'] as Timestamp).toDate(),
      cycleEnd: (map['cycleEnd'] as Timestamp).toDate(),
      expectedMinor: (map['expectedMinor'] as num).toInt(),
      confirmedMinor: (map['confirmedMinor'] as num?)?.toInt(),
      receivedMinor: (map['receivedMinor'] as num? ?? 0).toInt(),
      outstandingMinor: (map['outstandingMinor'] as num? ?? 0).toInt(),
      openExceptionCount: (map['openExceptionCount'] as num? ?? 0).toInt(),
      itemCount: (map['itemCount'] as num? ?? 0).toInt(),
      cancelledReason: map['cancelledReason'] as String?,
    );
  }

  bool get isCancelled => status == SettlementStatus.cancelled;
}

class SettlementItem {
  final String employeeId;
  final int accruedMinor;
  final int drawsDeductedMinor;
  final int netPayoutMinor;
  final int shortfallMinor;

  SettlementItem({
    required this.employeeId,
    required this.accruedMinor,
    required this.drawsDeductedMinor,
    required this.netPayoutMinor,
    required this.shortfallMinor,
  });

  factory SettlementItem.fromMap(Map<String, dynamic> map) {
    int v(String key) => (map[key] as num? ?? 0).toInt();
    return SettlementItem(
      employeeId: map['employeeId'] as String,
      accruedMinor: v('accruedMinor'),
      drawsDeductedMinor: v('drawsDeductedMinor'),
      netPayoutMinor: v('netPayoutMinor'),
      shortfallMinor: v('shortfallMinor'),
    );
  }
}

class SettlementException {
  final String id;
  final String type;
  final bool isOpen;
  final int expectedMinor;
  final int actualMinor;
  final int differenceMinor;
  final String? employeeId;
  final String? resolutionNote;

  SettlementException({
    required this.id,
    required this.type,
    required this.isOpen,
    required this.expectedMinor,
    required this.actualMinor,
    required this.differenceMinor,
    this.employeeId,
    this.resolutionNote,
  });

  factory SettlementException.fromMap(String id, Map<String, dynamic> map) {
    return SettlementException(
      id: id,
      type: map['type'] as String? ?? '',
      isOpen: map['status'] == 'open',
      expectedMinor: (map['expectedMinor'] as num? ?? 0).toInt(),
      actualMinor: (map['actualMinor'] as num? ?? 0).toInt(),
      differenceMinor: (map['differenceMinor'] as num? ?? 0).toInt(),
      employeeId: map['employeeId'] as String?,
      resolutionNote: map['resolutionNote'] as String?,
    );
  }

  String get title => switch (type) {
        'DEDUCTION_SHORTFALL' => 'Payroll deducted less than expected',
        'DEDUCTION_EXCESS' => 'Payroll deducted more than expected',
        'OVERPAYMENT' => 'More money received than confirmed',
        'INSUFFICIENT_PAY' => 'Pay did not cover the draw',
        _ => type,
      };
}
