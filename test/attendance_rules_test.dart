import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/utils/attendance_rules.dart';

void main() {
  final t0 = DateTime(2026, 10, 15, 6);
  const maxShift = Duration(hours: 14);
  Duration count(List<TimeSpan> spans, DateTime now) => countableDuration(spans, now, maxShift: maxShift);

  group('countableDuration (same vectors as the server)', () {
    test('overlapping records are counted once', () {
      final spans = List.generate(3, (_) => TimeSpan(t0, t0.add(const Duration(hours: 8))));
      expect(count(spans, t0.add(const Duration(hours: 9))), const Duration(hours: 8));
    });

    test('partly overlapping records add only the extra time', () {
      final spans = [
        TimeSpan(t0, t0.add(const Duration(hours: 6))),
        TimeSpan(t0.add(const Duration(hours: 4)), t0.add(const Duration(hours: 8))),
      ];
      expect(count(spans, t0.add(const Duration(hours: 9))), const Duration(hours: 8));
    });

    test('separate records add up', () {
      final spans = [
        TimeSpan(t0, t0.add(const Duration(hours: 4))),
        TimeSpan(t0.add(const Duration(hours: 5)), t0.add(const Duration(hours: 9))),
      ];
      expect(count(spans, t0.add(const Duration(hours: 10))), const Duration(hours: 8));
    });

    test('one record is capped, so a forgotten clock-out cannot run on', () {
      expect(count([TimeSpan(t0, null)], t0.add(const Duration(hours: 100))), maxShift);
      expect(count([TimeSpan(t0, t0.add(const Duration(hours: 60)))], t0.add(const Duration(hours: 100))), maxShift);
    });

    test('time that has not happened yet, or runs backwards, counts for nothing', () {
      expect(count([TimeSpan(t0.add(const Duration(hours: 5)), t0.add(const Duration(hours: 13)))], t0.add(const Duration(hours: 2))), Duration.zero);
      expect(count([TimeSpan(t0, t0.add(const Duration(hours: 10)))], t0.add(const Duration(hours: 4))), const Duration(hours: 4));
      expect(count([TimeSpan(t0.add(const Duration(hours: 8)), t0)], t0.add(const Duration(hours: 9))), Duration.zero);
    });
  });

  group('validateHoursRecord and validateReason', () {
    final now = DateTime(2026, 10, 20, 12);
    String? check(DateTime a, DateTime b, {int max = 14}) =>
        validateHoursRecord(clockIn: a, clockOut: b, now: now, maxShiftHours: max);

    test('a normal shift is fine', () {
      expect(check(DateTime(2026, 10, 19, 7), DateTime(2026, 10, 19, 16)), isNull);
    });
    test('wrong order, the future, too short and too long are refused', () {
      expect(check(DateTime(2026, 10, 19, 16), DateTime(2026, 10, 19, 7)), contains('after the start'));
      expect(check(DateTime(2026, 10, 20, 8), DateTime(2026, 10, 20, 18)), contains('not happened yet'));
      expect(check(DateTime(2026, 10, 19, 7), DateTime(2026, 10, 19, 7, 0, 30)), isNotNull);
      expect(check(DateTime(2026, 10, 18, 7), DateTime(2026, 10, 19, 7)), contains('14 hours'));
      expect(check(DateTime(2026, 10, 19, 7), DateTime(2026, 10, 19, 20), max: 10), contains('10 hours'));
    });
    test('a reason is required and kept plain', () {
      expect(validateReason(''), isNotNull);
      expect(validateReason('oops'), isNotNull);
      expect(validateReason('Forgot to clock out'), isNull);
      expect(validateReason('<script>'), isNotNull);
      expect(validateReason('x' * 301), isNotNull);
    });
  });

  group('parseAttendanceCsv', () {
    final now = DateTime(2026, 10, 20, 12);
    final ids = {'DG-101': 'uid-1', 'DG-102': 'uid-2'};
    AttendanceParse parse(String text, {int max = 14}) =>
        parseAttendanceCsv(text, employeeIdByNumber: ids, now: now, maxShiftHours: max);

    test('reads a file with a header, blank lines and both date styles', () {
      final p = parse('employee_number,date,clock_in,clock_out\n'
          'DG-101,2026-10-19,07:00,16:00\n'
          '\n'
          'DG-102,19/10/2026,07:30,17:00\n');
      expect(p.errors, isEmpty);
      expect(p.rows.length, 2);
      expect(p.rows[0].employeeId, 'uid-1');
      expect(p.rows[0].clockIn, DateTime(2026, 10, 19, 7));
      expect(p.rows[1].clockOut, DateTime(2026, 10, 19, 17));
    });

    test('a block pasted from Excel (tabs) or with semicolons works', () {
      expect(parse('DG-101\t2026-10-19\t07:00\t16:00').rows.length, 1);
      expect(parse('DG-101;2026-10-19;07:00;16:00').rows.length, 1);
    });

    test('a night shift ends the next day', () {
      final p = parse('DG-101,2026-10-18,22:00,06:00');
      expect(p.errors, isEmpty);
      expect(p.rows.single.clockOut, DateTime(2026, 10, 19, 6));
    });

    test('every bad line is explained with its line number and the rest still load', () {
      final p = parse('DG-101,2026-10-19,07:00,16:00\n'
          'DG-999,2026-10-19,07:00,16:00\n'
          'DG-101,not-a-date,07:00,16:00\n'
          'DG-101,2026-10-19,7am,16:00\n'
          'DG-101,2026-10-19,07:00\n'
          'DG-101,2026-10-19,00:00,23:59\n'
          'DG-101,2026-10-25,07:00,16:00\n'
          'DG-101,2026-02-30,07:00,16:00');
      expect(p.rows.length, 1);
      expect(p.errors.length, 7);
      expect(p.errors[0], startsWith('Line 2:'));
      expect(p.errors[0], contains('DG-999'));
      expect(p.errors.any((e) => e.startsWith('Line 3:') && e.contains('not a date')), isTrue);
      expect(p.errors.any((e) => e.startsWith('Line 6:') && e.contains('14 hours')), isTrue);
      expect(p.errors.any((e) => e.startsWith('Line 7:') && e.contains('not happened yet')), isTrue);
    });

    test('the same record twice in one file is counted once', () {
      final p = parse('DG-101,2026-10-19,07:00,16:00\nDG-101,2026-10-19,07:00,15:00');
      expect(p.rows.length, 1);
      expect(p.duplicatesInFile, 1);
    });

    test('a very long file is cut off with a message', () {
      final lines = List.generate(5, (i) => 'DG-101,2026-10-${10 + i},07:00,16:00').join('\n');
      final p = parseAttendanceCsv(lines, employeeIdByNumber: ids, now: now, maxShiftHours: 14, maxRows: 3);
      expect(p.rows.length, 3);
      expect(p.errors.single, contains('first 3'));
    });
  });
}
