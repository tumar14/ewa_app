import 'employee.dart';

// ── Payday rule ───────────────────────────────────────────────────────────────

enum PaydayType {
  fixedDayOfMonth,    // e.g. always the 25th (clamped to month end)
  lastDayOfMonth,     // always the final calendar day of the month
  lastWeekdayOfMonth, // e.g. last Friday of the month
}

class PaydayRule {
  /// Which kind of payday schedule this is.
  final PaydayType type;

  /// Day of month (1–28). Only used when [type] == [PaydayType.fixedDayOfMonth].
  /// Clamped to the actual last day of the month at runtime, so setting 31
  /// correctly resolves to 28/29/30/31 depending on the month.
  final int dayOfMonth;

  /// ISO weekday (1 = Monday … 5 = Friday).
  /// Only used when [type] == [PaydayType.lastWeekdayOfMonth].
  final int weekday;

  const PaydayRule({
    this.type = PaydayType.lastDayOfMonth,
    this.dayOfMonth = 25,
    this.weekday = 5, // Friday
  });

  factory PaydayRule.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PaydayRule();
    return PaydayRule(
      type: PaydayType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => PaydayType.lastDayOfMonth,
      ),
      dayOfMonth: (map['dayOfMonth'] as num?)?.toInt() ?? 25,
      weekday: (map['weekday'] as num?)?.toInt() ?? 5,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'dayOfMonth': dayOfMonth,
        'weekday': weekday,
      };

  PaydayRule copyWith({PaydayType? type, int? dayOfMonth, int? weekday}) {
    return PaydayRule(
      type: type ?? this.type,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      weekday: weekday ?? this.weekday,
    );
  }
}

// ── App settings ──────────────────────────────────────────────────────────────

class AppSettings {
  final String companyName;
  final double maxDrawPercent;
  final double feePercent;
  final int maxDrawsPerCycle;
  final ClockSource clockSource;
  final DisbursementMethod disbursementPolicy;
  final PaydayRule paydayRule;

  AppSettings({
    this.companyName = '',
    this.maxDrawPercent = 0.5,
    this.feePercent = 0.05,
    this.maxDrawsPerCycle = 2,
    this.clockSource = ClockSource.manual,
    this.disbursementPolicy = DisbursementMethod.bankTransfer,
    this.paydayRule = const PaydayRule(),
  });

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      companyName: map['companyName'] as String? ?? '',
      maxDrawPercent: (map['maxDrawPercent'] as num?)?.toDouble() ?? 0.5,
      feePercent: (map['feePercent'] as num?)?.toDouble() ?? 0.05,
      maxDrawsPerCycle: (map['maxDrawsPerCycle'] as num?)?.toInt() ?? 2,
      clockSource: ClockSource.values.firstWhere(
        (e) => e.name == map['clockSource'],
        orElse: () => ClockSource.manual,
      ),
      disbursementPolicy: DisbursementMethod.values.firstWhere(
        (e) => e.name == map['disbursementPolicy'],
        orElse: () => DisbursementMethod.bankTransfer,
      ),
      paydayRule: PaydayRule.fromMap(
          map['paydayRule'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toMap() => {
        'companyName': companyName,
        'maxDrawPercent': maxDrawPercent,
        'feePercent': feePercent,
        'maxDrawsPerCycle': maxDrawsPerCycle,
        'clockSource': clockSource.name,
        'disbursementPolicy': disbursementPolicy.name,
        'paydayRule': paydayRule.toMap(),
      };

  AppSettings copyWith({
    String? companyName,
    double? maxDrawPercent,
    double? feePercent,
    int? maxDrawsPerCycle,
    ClockSource? clockSource,
    DisbursementMethod? disbursementPolicy,
    PaydayRule? paydayRule,
  }) {
    return AppSettings(
      companyName: companyName ?? this.companyName,
      maxDrawPercent: maxDrawPercent ?? this.maxDrawPercent,
      feePercent: feePercent ?? this.feePercent,
      maxDrawsPerCycle: maxDrawsPerCycle ?? this.maxDrawsPerCycle,
      clockSource: clockSource ?? this.clockSource,
      disbursementPolicy: disbursementPolicy ?? this.disbursementPolicy,
      paydayRule: paydayRule ?? this.paydayRule,
    );
  }
}
