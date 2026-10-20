/// What the public website offers, set by the platform admin
/// (platform_config/website). Mirrors functions/src/industries.ts; the server
/// re-checks every submission against the saved list.
const kIndustryOther = 'Other';
const kMaxIndustries = 50;
const kMaxIndustryLength = 100;

const kDefaultIndustries = <String>[
  'Garment and textile manufacturing',
  'Other manufacturing',
  'Agriculture and agro-processing',
  'Retail and wholesale',
  'Hospitality and tourism',
  'Construction',
  'Mining and quarrying',
  'Transport and logistics',
  'Security services',
  'Health care',
  'Education',
  'Financial services',
  'Public sector',
  kIndustryOther,
];

/// Trims and collapses runs of whitespace.
String cleanIndustryName(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Why [raw] cannot be added to [existing], or null if it can.
String? industryProblem(String raw, List<String> existing) {
  final name = cleanIndustryName(raw);
  if (name.isEmpty) return 'Type an industry name first.';
  if (name.length > kMaxIndustryLength) {
    return 'Keep it to $kMaxIndustryLength characters or fewer.';
  }
  if (name.codeUnits.any((c) => c == 60 || c == 62 || c < 32)) {
    return 'Letters, numbers and ordinary punctuation only (no < or >).';
  }
  if (existing.any((e) => e.toLowerCase() == name.toLowerCase())) {
    return '"$name" is already in the list.';
  }
  if (existing.length >= kMaxIndustries) {
    return 'The list can hold at most $kMaxIndustries industries.';
  }
  return null;
}

/// The saved list, or the defaults if nothing usable is saved.
List<String> industriesFromMap(Map<String, dynamic>? data) {
  final raw = data?['industries'];
  final out = <String>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is! String) continue;
      final name = cleanIndustryName(item);
      if (industryProblem(name, out) == null) out.add(name);
    }
  }
  return out.isEmpty ? List.of(kDefaultIndustries) : out;
}
