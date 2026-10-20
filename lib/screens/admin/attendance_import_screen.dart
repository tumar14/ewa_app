import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/employee_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/settings_providers.dart';
import '../../utils/attendance_rules.dart';
import '../../widgets/glass_components.dart';

const _example = 'employee_number,date,clock_in,clock_out\n'
    'DG-101,2026-10-19,07:00,16:00\n'
    'DG-102,2026-10-19,07:30,17:00\n'
    'DG-103,2026-10-18,22:00,06:00';

/// Upload attendance from another system or a spreadsheet: paste the rows (a block
/// copied from Excel works). Every line is checked before anything is saved; a
/// record already in the system is skipped, so the same file can be sent twice.
class AttendanceImportScreen extends ConsumerStatefulWidget {
  const AttendanceImportScreen({super.key});

  @override
  ConsumerState<AttendanceImportScreen> createState() => _AttendanceImportScreenState();
}

class _AttendanceImportScreenState extends ConsumerState<AttendanceImportScreen> {
  final _text = TextEditingController();
  final _reason = TextEditingController();
  AttendanceParse? _parsed;
  int _alreadyThere = 0;
  bool _busy = false;
  String? _message;
  String? _problem;

  @override
  void dispose() {
    _text.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _message = null;
      _problem = null;
      _parsed = null;
    });
    try {
      final employees = ref.read(allEmployeesProvider).valueOrNull ?? const [];
      final byNumber = <String, String>{};
      final ambiguous = <String>{};
      for (final e in employees) {
        if (e.employeeNumber.isEmpty) continue;
        if (byNumber.containsKey(e.employeeNumber)) ambiguous.add(e.employeeNumber);
        byNumber[e.employeeNumber] = e.id;
      }
      byNumber.removeWhere((number, _) => ambiguous.contains(number));
      final settings = ref.read(appSettingsProvider).valueOrNull;
      final parsed = parseAttendanceCsv(
        _text.text,
        employeeIdByNumber: byNumber,
        now: DateTime.now(),
        maxShiftHours: settings?.maxShiftHours ?? kDefaultMaxShiftHours,
      );
      final existing = await ref.read(timeSessionRepositoryProvider).existingKeys(parsed.rows);
      setState(() {
        _parsed = AttendanceParse(
          parsed.rows,
          [
            ...parsed.errors,
            for (final n in ambiguous) 'Employee number "$n" belongs to more than one person, so it cannot be matched.',
          ],
          parsed.duplicatesInFile,
        );
        _alreadyThere = parsed.rows.where((r) => existing.contains(r.key)).length;
      });
    } catch (e) {
      setState(() => _problem = 'Could not check the file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final parsed = _parsed;
    if (parsed == null || parsed.rows.isEmpty) return;
    final reasonProblem = validateReason(_reason.text);
    if (reasonProblem != null) {
      setState(() => _problem = 'Say where this file came from. $reasonProblem');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final result = await ref.read(timeSessionRepositoryProvider).importAttendance(
            rows: parsed.rows,
            reason: _reason.text,
            editorId: FirebaseAuth.instance.currentUser!.uid,
          );
      final signOff = (ref.read(appSettingsProvider).valueOrNull?.countOnlyReviewedHours ?? false)
          ? ' This company only counts signed-off hours, so a supervisor must sign these days off before they count towards advances.'
          : '';
      setState(() {
        _message = 'Saved ${result.written} record${result.written == 1 ? '' : 's'}'
            '${result.skipped > 0 ? ' and skipped ${result.skipped} that were already there' : ''}.$signOff';
        _parsed = null;
        _text.clear();
      });
    } on FirebaseException catch (e) {
      setState(() => _problem = e.code == 'permission-denied'
          ? 'Not allowed. Check that Admin Settings still allow attendance uploads.'
          : 'Could not save: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final allowed = settings?.allowAttendanceImport ?? true;
    final theme = Theme.of(context);
    final parsed = _parsed;
    final ready = parsed == null ? 0 : parsed.rows.length - _alreadyThere;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Upload attendance')),
      body: GlassBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!allowed)
              GlassCard(
                radius: 16,
                padding: const EdgeInsets.all(16),
                child: const Text('Attendance uploads are switched off for this company. Turn them on in Admin Settings under Attendance & hours.'),
              ),
            GlassCard(
              radius: 16,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Format', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'One line per shift: employee number, date, clock in, clock out. Use the employee numbers in your '
                    'roster. Dates are 2026-10-19 or 19/10/2026 and times are 07:30. If the clock out is earlier than '
                    'the clock in, the shift ends the next day. You can paste rows copied from Excel.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  const SelectableText(_example, style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(const ClipboardData(text: _example)),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy example'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              enabled: allowed && !_busy,
              minLines: 6,
              maxLines: 14,
              decoration: const InputDecoration(labelText: 'Paste attendance rows here', alignLabelWithHint: true),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onChanged: (_) => setState(() {
                _parsed = null;
                _message = null;
              }),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: allowed && !_busy && _text.text.trim().isNotEmpty ? _check : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Check the file'),
            ),
            if (parsed != null) ...[
              const SizedBox(height: 12),
              GlassCard(
                radius: 16,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$ready record${ready == 1 ? '' : 's'} ready to save', style: theme.textTheme.titleMedium),
                    if (_alreadyThere > 0) Text('$_alreadyThere already recorded, will be skipped.'),
                    if (parsed.duplicatesInFile > 0) Text('${parsed.duplicatesInFile} repeated in the file, counted once.'),
                    if (parsed.errors.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('${parsed.errors.length} line${parsed.errors.length == 1 ? '' : 's'} need fixing and will not be saved:',
                          style: TextStyle(color: theme.colorScheme.error)),
                      for (final e in parsed.errors.take(12)) Text(e, style: theme.textTheme.bodySmall),
                      if (parsed.errors.length > 12) Text('…and ${parsed.errors.length - 12} more.', style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (ready > 0) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Where did this file come from? (required)',
                    helperText: 'For example: time clock export, week ending 19 Oct',
                  ),
                ),
                FilledButton(
                  onPressed: _busy ? null : _import,
                  child: Text(_busy ? 'Saving…' : 'Save $ready record${ready == 1 ? '' : 's'}'),
                ),
              ],
            ],
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!),
              ),
          ],
        ),
      ),
    );
  }
}
