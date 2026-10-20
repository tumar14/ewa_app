import 'package:flutter/material.dart';
import '../../utils/attendance_rules.dart';

/// What the admin entered to add or correct a record.
class HoursEdit {
  final DateTime clockIn;
  final DateTime clockOut;
  final String reason;
  const HoursEdit(this.clockIn, this.clockOut, this.reason);
}

/// Dialog to add missing hours or correct a record: a date, a start and end time
/// and a mandatory reason. It only returns something the rules would accept
/// (a real period, not in the future, within the company's longest shift).
Future<HoursEdit?> showHoursEditDialog(
  BuildContext context, {
  required String title,
  required int maxShiftHours,
  DateTime? initialIn,
  DateTime? initialOut,
  DateTime? now,
}) {
  return showDialog<HoursEdit>(
    context: context,
    builder: (_) => _HoursEditDialog(
      title: title,
      maxShiftHours: maxShiftHours,
      initialIn: initialIn,
      initialOut: initialOut,
      now: now ?? DateTime.now(),
    ),
  );
}

class _HoursEditDialog extends StatefulWidget {
  final String title;
  final int maxShiftHours;
  final DateTime? initialIn;
  final DateTime? initialOut;
  final DateTime now;
  const _HoursEditDialog({
    required this.title,
    required this.maxShiftHours,
    required this.initialIn,
    required this.initialOut,
    required this.now,
  });

  @override
  State<_HoursEditDialog> createState() => _HoursEditDialogState();
}

class _HoursEditDialogState extends State<_HoursEditDialog> {
  late DateTime _in = widget.initialIn ?? DateTime(widget.now.year, widget.now.month, widget.now.day, 7);
  late DateTime _out = widget.initialOut ?? DateTime(widget.now.year, widget.now.month, widget.now.day, 16);
  final _reason = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmt(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}  ${_two(t.hour)}:${_two(t.minute)}';

  Future<DateTime?> _pick(DateTime current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current.isAfter(widget.now) ? widget.now : current,
      firstDate: DateTime(widget.now.year - 2),
      lastDate: widget.now,
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _submit() {
    final problem = validateHoursRecord(
          clockIn: _in,
          clockOut: _out,
          now: widget.now,
          maxShiftHours: widget.maxShiftHours,
        ) ??
        validateReason(_reason.text);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context, HoursEdit(_in, _out, _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final length = _out.difference(_in);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Started'),
              subtitle: Text(_fmt(_in)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final t = await _pick(_in);
                if (t != null) setState(() => _in = t);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Finished'),
              subtitle: Text(_fmt(_out)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final t = await _pick(_out);
                if (t != null) setState(() => _out = t);
              },
            ),
            if (length > Duration.zero)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${length.inHours}h ${length.inMinutes % 60}m', style: Theme.of(context).textTheme.bodySmall),
              ),
            TextField(
              controller: _reason,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                helperText: 'For example: forgot to clock out, phone had no signal',
              ),
            ),
            if (_problem != null)
              Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Asks for a reason before cancelling a record.
Future<String?> askReason(BuildContext context, {required String title, required String action}) {
  final ctrl = TextEditingController();
  String? problem;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              maxLength: 300,
              maxLines: 2,
              decoration: InputDecoration(labelText: 'Reason (required)', errorText: problem),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final p = validateReason(ctrl.text);
              if (p != null) {
                setState(() => problem = p);
                return;
              }
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(action),
          ),
        ],
      ),
    ),
  ).whenComplete(ctrl.dispose);
}
