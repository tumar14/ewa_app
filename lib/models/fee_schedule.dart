/// How a company charges its service fee: a percentage, or a tariff table of
/// amount bands (like a mobile-money tariff).
///
/// This mirrors functions/src/feeSchedule.ts. The app uses it only to preview
/// the fee and to validate what an admin enters; the server works out the real
/// fee when the advance is requested. All money here is integer cents.
class FeeTier {
  /// Highest amount (cents) this band covers; null means "and above".
  final int? upToMinor;
  final int flatMinor;
  final double percent;

  const FeeTier({required this.upToMinor, this.flatMinor = 0, this.percent = 0});

  factory FeeTier.fromMap(Map<String, dynamic> map) => FeeTier(
        upToMinor: (map['upToMinor'] as num?)?.toInt(),
        flatMinor: (map['flatMinor'] as num?)?.toInt() ?? 0,
        percent: (map['percent'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'upToMinor': upToMinor,
        'flatMinor': flatMinor,
        'percent': percent,
      };

  FeeTier copyWith({int? upToMinor, bool clearUpTo = false, int? flatMinor, double? percent}) => FeeTier(
        upToMinor: clearUpTo ? null : (upToMinor ?? this.upToMinor),
        flatMinor: flatMinor ?? this.flatMinor,
        percent: percent ?? this.percent,
      );
}

enum FeeMode { percent, tiered }

class FeeSchedule {
  /// No single fee component may exceed half the amount.
  static const maxPercent = 0.5;

  final FeeMode mode;
  final double percent;
  final List<FeeTier> tiers;

  const FeeSchedule.percent(this.percent)
      : mode = FeeMode.percent,
        tiers = const [];

  const FeeSchedule.tiered(this.tiers)
      : mode = FeeMode.tiered,
        percent = 0;

  /// Reads a settings/app document, tolerating older ones that only have feePercent.
  factory FeeSchedule.fromMap(Map<String, dynamic> map) {
    if (map['feeMode'] == 'tiered') {
      final raw = map['feeTiers'];
      final tiers = raw is List
          ? raw.whereType<Map>().map((m) => FeeTier.fromMap(Map<String, dynamic>.from(m))).toList()
          : <FeeTier>[];
      return FeeSchedule.tiered(tiers);
    }
    return FeeSchedule.percent((map['feePercent'] as num?)?.toDouble() ?? 0.05);
  }

  /// The fields to merge into settings/app. feePercent is always written so
  /// older app versions keep working.
  Map<String, dynamic> toMap() => {
        'feeMode': mode.name,
        'feePercent': mode == FeeMode.percent ? percent : 0.05,
        'feeTiers': mode == FeeMode.tiered ? tiers.map((t) => t.toMap()).toList() : <Map<String, dynamic>>[],
      };

  bool get isPercent => mode == FeeMode.percent;

  /// Null when usable, otherwise a plain-language reason. Same rules as the server.
  String? validate() {
    bool okPercent(double p) => p.isFinite && p >= 0 && p <= maxPercent;
    if (isPercent) return okPercent(percent) ? null : 'The fee percentage must be between 0% and 50%.';
    if (tiers.isEmpty) return 'Add at least one fee band.';
    var previous = 0;
    for (final (i, t) in tiers.indexed) {
      final label = 'Band ${i + 1}';
      final last = i == tiers.length - 1;
      if (t.flatMinor < 0) return '$label: the flat fee must be zero or more.';
      if (!okPercent(t.percent)) return '$label: the percentage must be between 0% and 50%.';
      if (t.upToMinor == null) {
        if (!last) return '$label: only the last band can have no upper limit.';
      } else if (t.upToMinor! <= previous) {
        return "$label: the upper limit must be higher than the previous band's.";
      }
      if (t.upToMinor != null) previous = t.upToMinor!;
    }
    return null;
  }

  /// The largest amount allowed (cents), or null when there is no limit.
  int? get maxAmountMinor => isPercent ? null : tiers.last.upToMinor;

  /// The fee in cents for an amount, or null when the amount is outside every band.
  int? feeMinorFor(int amountMinor) {
    if (isPercent) return (amountMinor * percent).round();
    for (final t in tiers) {
      if (t.upToMinor == null || amountMinor <= t.upToMinor!) {
        return (t.flatMinor + amountMinor * t.percent).round();
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is FeeSchedule &&
      other.mode == mode &&
      other.percent == percent &&
      other.tiers.length == tiers.length &&
      [for (var i = 0; i < tiers.length; i++) tiers[i].toMap().toString() == other.tiers[i].toMap().toString()]
          .every((same) => same);

  @override
  int get hashCode => Object.hash(mode, percent, tiers.length);
}
