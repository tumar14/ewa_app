/// Rules for time records that are typed in or uploaded. Mirrors the server's view
/// of which time counts (functions/src/hours.ts, drawRules.ts countableMs), so what
/// the app shows as earned is what the server will allow.
library;

const kDefaultMaxShiftHours = 14;
const kMinShiftHours = 1;
const kMaxShiftHoursLimit = 24;

/// A span of recorded time, for counting.
class TimeSpan {
  final DateTime start;
  final DateTime? end; // null = still open
  const TimeSpan(this.start, this.end);
}

/// Paid time in [spans] as at [now]: nothing that has not happened yet, no single
/// record longer than [maxShift], and overlapping records merged so the same hour
/// is never counted twice.
Duration countableDuration(Iterable<TimeSpan> spans, DateTime now, {Duration? maxShift}) {
  final cleaned = <(DateTime, DateTime)>[];
  for (final s in spans) {
    if (!s.start.isBefore(now)) continue;
    var end = s.end ?? now;
    if (end.isAfter(now)) end = now;
    if (!end.isAfter(s.start)) continue;
    if (maxShift != null && end.isAfter(s.start.add(maxShift))) end = s.start.add(maxShift);
    cleaned.add((s.start, end));
  }
  cleaned.sort((a, b) => a.$1.compareTo(b.$1));
  var total = Duration.zero;
  DateTime? from;
  DateTime? to;
  for (final (a, b) in cleaned) {
    if (to == null || a.isAfter(to)) {
      if (from != null && to != null) total += to.difference(from);
      from = a;
      to = b;
    } else if (b.isAfter(to)) {
      to = b;
    }
  }
  if (from != null && to != null) total += to.difference(from);
  return total;
}

/// Why a typed-in or uploaded record cannot be saved, or null if it can.
String? validateHoursRecord({
  required DateTime clockIn,
  required DateTime clockOut,
  required DateTime now,
  required int maxShiftHours,
}) {
  if (!clockOut.isAfter(clockIn)) return 'The end time must be after the start time.';
  if (clockOut.isAfter(now.add(const Duration(minutes: 1)))) return 'Hours that have not happened yet cannot be recorded.';
  final length = clockOut.difference(clockIn);
  if (length < const Duration(minutes: 1)) return 'A record must be at least one minute long.';
  if (length > Duration(hours: maxShiftHours)) {
    return 'A single record cannot be longer than $maxShiftHours hours. Split it into separate shifts.';
  }
  return null;
}

/// A reason is mandatory for every manual change, so the record explains itself later.
String? validateReason(String reason) {
  final r = reason.trim();
  if (r.length < 5) return 'Give a reason of at least 5 characters.';
  if (r.length > 300) return 'Keep the reason under 300 characters.';
  if (r.codeUnits.any((c) => c == 60 || c == 62 || c < 32)) return 'The reason cannot contain < or > or control characters.';
  return null;
}

/// One row of an attendance upload, matched to an employee.
class ImportRow {
  final int line;
  final String employeeNumber;
  final String employeeId;
  final DateTime clockIn;
  final DateTime clockOut;
  const ImportRow(this.line, this.employeeNumber, this.employeeId, this.clockIn, this.clockOut);
  String get key => '$employeeId|${clockIn.millisecondsSinceEpoch}';
}

class AttendanceParse {
  final List<ImportRow> rows;
  final List<String> errors;
  final int duplicatesInFile;
  const AttendanceParse(this.rows, this.errors, this.duplicatesInFile);
}

DateTime? _date(String s) {
  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  int y, mo, d;
  if (m != null) {
    y = int.parse(m.group(1)!);
    mo = int.parse(m.group(2)!);
    d = int.parse(m.group(3)!);
  } else {
    m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
    if (m == null) return null;
    d = int.parse(m.group(1)!);
    mo = int.parse(m.group(2)!);
    y = int.parse(m.group(3)!);
  }
  final dt = DateTime(y, mo, d);
  return dt.year == y && dt.month == mo && dt.day == d ? dt : null;
}

(int, int)? _time(String s) {
  final m = RegExp(r'^(\d{1,2})[:.h](\d{2})$').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  return h <= 23 && mi <= 59 ? (h, mi) : null;
}

/// Reads an attendance upload: one record per line with
/// `employee number, date, clock in, clock out` (comma, semicolon or tab separated,
/// so a block pasted from Excel works). Dates are `2026-10-19` or `19/10/2026`,
/// times are `07:30`. A clock-out earlier than the clock-in is a night shift that
/// ends the next day. Every line is checked; a bad line is reported and skipped.
AttendanceParse parseAttendanceCsv(
  String text, {
  required Map<String, String> employeeIdByNumber,
  required DateTime now,
  required int maxShiftHours,
  int maxRows = 2000,
}) {
  final rows = <ImportRow>[];
  final errors = <String>[];
  final seen = <String>{};
  var duplicates = 0;
  final lines = text.split(RegExp(r'\r?\n'));
  var counted = 0;
  var seenAnyLine = false;
  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i].trim();
    if (raw.isEmpty) continue;
    final cells = raw.split(RegExp(r'[,;\t]')).map((c) => c.trim()).toList();
    final first = cells.first.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final isHeader = !seenAnyLine && (first == 'employeenumber' || first == 'employee' || first == 'empno');
    seenAnyLine = true;
    if (isHeader) continue;
    counted++;
    if (counted > maxRows) {
      errors.add('Only the first $maxRows records are read. Upload the rest separately.');
      break;
    }
    final n = i + 1;
    if (cells.length < 4) {
      errors.add('Line $n: needs employee number, date, clock in and clock out.');
      continue;
    }
    final number = cells[0];
    final id = employeeIdByNumber[number];
    if (id == null) {
      errors.add('Line $n: no employee with number "$number" in this company.');
      continue;
    }
    final date = _date(cells[1]);
    final tin = _time(cells[2]);
    final tout = _time(cells[3]);
    if (date == null) {
      errors.add('Line $n: "${cells[1]}" is not a date. Use 2026-10-19 or 19/10/2026.');
      continue;
    }
    if (tin == null || tout == null) {
      errors.add('Line $n: times must look like 07:30.');
      continue;
    }
    final clockIn = DateTime(date.year, date.month, date.day, tin.$1, tin.$2);
    var clockOut = DateTime(date.year, date.month, date.day, tout.$1, tout.$2);
    if (!clockOut.isAfter(clockIn)) clockOut = clockOut.add(const Duration(days: 1));
    final problem = validateHoursRecord(clockIn: clockIn, clockOut: clockOut, now: now, maxShiftHours: maxShiftHours);
    if (problem != null) {
      errors.add('Line $n: $problem');
      continue;
    }
    final row = ImportRow(n, number, id, clockIn, clockOut);
    if (!seen.add(row.key)) {
      duplicates++;
      continue;
    }
    rows.add(row);
  }
  return AttendanceParse(rows, errors, duplicates);
}
