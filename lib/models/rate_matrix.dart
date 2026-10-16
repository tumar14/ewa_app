class RateMatrix {
  // rates[department][role] = hourly rate in SZL
  final Map<String, Map<String, double>> rates;

  const RateMatrix({this.rates = const {}});

  factory RateMatrix.empty() => const RateMatrix(rates: {});

  factory RateMatrix.fromMap(Map<String, dynamic>? map) {
    if (map == null) return RateMatrix.empty();
    final rates = <String, Map<String, double>>{};
    for (final entry in map.entries) {
      if (entry.value is Map) {
        rates[entry.key] = (entry.value as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()),
        );
      }
    }
    return RateMatrix(rates: rates);
  }

  Map<String, dynamic> toMap() => {
        for (final dept in rates.entries)
          dept.key: dept.value.map((k, v) => MapEntry(k, v)),
      };

  double? rateFor(String department, String role) =>
      rates[department]?[role];

  RateMatrix withRate(String department, String role, double? rate) {
    final updated = Map<String, Map<String, double>>.from(
      rates.map((d, rs) => MapEntry(d, Map<String, double>.from(rs))),
    );
    if (rate == null || rate <= 0) {
      updated[department]?.remove(role);
      if (updated[department]?.isEmpty ?? false) updated.remove(department);
    } else {
      updated[department] ??= {};
      updated[department]![role] = rate;
    }
    return RateMatrix(rates: updated);
  }
}
