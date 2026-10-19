import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/fee_schedule.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';

/// Lets management choose how the service fee is charged: one percentage, or a
/// tariff table of amount bands (like a mobile-money tariff), with a live
/// preview of what workers would pay. Reports the schedule and, if what has
/// been typed cannot be used yet, a plain-language reason.
class FeeScheduleEditor extends StatefulWidget {
  final FeeSchedule initial;
  final void Function(FeeSchedule schedule, String? problem) onChanged;

  const FeeScheduleEditor({super.key, required this.initial, required this.onChanged});

  @override
  State<FeeScheduleEditor> createState() => _FeeScheduleEditorState();
}

class _Row {
  final TextEditingController upTo;
  final TextEditingController flat;
  final TextEditingController percent;
  _Row({String upTo = '', String flat = '', String percent = ''})
      : upTo = TextEditingController(text: upTo),
        flat = TextEditingController(text: flat),
        percent = TextEditingController(text: percent);

  void dispose() {
    upTo.dispose();
    flat.dispose();
    percent.dispose();
  }
}

class _FeeScheduleEditorState extends State<FeeScheduleEditor> {
  late FeeMode _mode;
  late double _percent;
  final List<_Row> _rows = [];
  bool _openTop = true;

  static String _money(int minor) => (minor / 100).toStringAsFixed(minor % 100 == 0 ? 0 : 2);
  static String _pct(double fraction) {
    final p = fraction * 100;
    return p == 0 ? '' : p.toStringAsFixed(p % 1 == 0 ? 0 : 2);
  }

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _mode = s.mode;
    _percent = s.isPercent ? s.percent : 0.05;
    if (s.isPercent || s.tiers.isEmpty) {
      _rows.addAll([
        _Row(upTo: '50', flat: '1'),
        _Row(upTo: '200', flat: '3'),
        _Row(upTo: '1000', flat: '6', percent: '0.5'),
      ]);
      _openTop = true;
    } else {
      for (final t in s.tiers) {
        _rows.add(_Row(
          upTo: t.upToMinor == null ? '' : _money(t.upToMinor!),
          flat: t.flatMinor == 0 ? '' : _money(t.flatMinor),
          percent: _pct(t.percent),
        ));
      }
      _openTop = s.tiers.last.upToMinor == null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Builds the schedule from what is typed. The problem is set when a field
  /// cannot be read at all; otherwise validate() judges the schedule.
  (FeeSchedule, String?) _build() {
    if (_mode == FeeMode.percent) return (FeeSchedule.percent(_percent), null);
    final tiers = <FeeTier>[];
    for (final (i, r) in _rows.indexed) {
      final last = i == _rows.length - 1;
      final open = last && _openTop;
      final upTo = open ? null : CurrencyFormatter.parseMinor(r.upTo.text);
      final flat = r.flat.text.trim().isEmpty ? 0 : CurrencyFormatter.parseMinor(r.flat.text);
      final pctText = r.percent.text.trim();
      final pct = pctText.isEmpty ? 0.0 : double.tryParse(pctText);
      if (!open && upTo == null) return (FeeSchedule.tiered(tiers), 'Band ${i + 1}: enter the upper limit as an amount, like 50 or 50.00.');
      if (flat == null) return (FeeSchedule.tiered(tiers), 'Band ${i + 1}: enter the flat fee as an amount, like 3 or 3.50.');
      if (pct == null) return (FeeSchedule.tiered(tiers), 'Band ${i + 1}: enter the percentage as a number, like 0.5.');
      tiers.add(FeeTier(upToMinor: upTo, flatMinor: flat, percent: pct / 100));
    }
    return (FeeSchedule.tiered(tiers), null);
  }

  void _report() {
    final (schedule, parseProblem) = _build();
    widget.onChanged(schedule, parseProblem ?? schedule.validate());
    if (mounted) setState(() {});
  }

  void _addRow() {
    setState(() {
      // New bands go before an open top band, which must stay last.
      final at = _openTop && _rows.isNotEmpty ? _rows.length - 1 : _rows.length;
      _rows.insert(at, _Row());
    });
    _report();
  }

  void _removeRow(int i) {
    if (_rows.length <= 1) return;
    setState(() => _rows.removeAt(i).dispose());
    _report();
  }

  Widget _field(TextEditingController c, String label, {String? prefix, String? suffix, bool enabled = true, String? hint}) {
    return TextField(
      controller: c,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onChanged: (_) => _report(),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (schedule, parseProblem) = _build();
    final problem = parseProblem ?? schedule.validate();
    final muted = TextStyle(fontSize: 12, color: context.onSurface(0.60));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Service fee', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<FeeMode>(
          segments: const [
            ButtonSegment(value: FeeMode.percent, label: Text('Percentage'), icon: Icon(Icons.percent)),
            ButtonSegment(value: FeeMode.tiered, label: Text('Tariff table'), icon: Icon(Icons.table_rows_outlined)),
          ],
          selected: {_mode},
          onSelectionChanged: (v) {
            setState(() => _mode = v.first);
            _report();
          },
        ),
        const SizedBox(height: 12),
        if (_mode == FeeMode.percent) ...[
          Text('Fee: ${(_percent * 100).toStringAsFixed(1)}% of the amount advanced'),
          Slider(
            value: _percent.clamp(0.0, 0.15),
            min: 0,
            max: 0.15,
            divisions: 30,
            label: '${(_percent * 100).toStringAsFixed(1)}%',
            onChanged: (v) {
              setState(() => _percent = v);
              _report();
            },
          ),
        ] else ...[
          Text('The fee depends on the amount. Each band has an upper limit, a flat fee and, if you want, a percentage on top.', style: muted),
          const SizedBox(height: 10),
          for (final (i, r) in _rows.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Band ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_rows.length > 1)
                        IconButton(
                          tooltip: 'Remove band ${i + 1}',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _removeRow(i),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          r.upTo,
                          i == _rows.length - 1 && _openTop ? 'Up to' : 'Up to (E)',
                          prefix: i == _rows.length - 1 && _openTop ? null : 'E',
                          enabled: !(i == _rows.length - 1 && _openTop),
                          hint: i == _rows.length - 1 && _openTop ? 'and above' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _field(r.flat, 'Flat fee', prefix: 'E')),
                      const SizedBox(width: 8),
                      Expanded(child: _field(r.percent, '+ Percent', suffix: '%')),
                    ],
                  ),
                ],
              ),
            ),
          Row(
            children: [
              TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 18), label: const Text('Add band')),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Last band covers any larger amount'),
            subtitle: Text(
              _openTop
                  ? 'No upper limit on the last band.'
                  : 'Amounts above the last band\'s limit are not allowed. This also caps the size of one advance.',
              style: muted,
            ),
            value: _openTop,
            onChanged: (v) {
              setState(() => _openTop = v);
              _report();
            },
          ),
        ],
        const SizedBox(height: 4),
        if (problem != null)
          Text(problem, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13))
        else ...[
          Text('What workers would pay', style: muted.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final amount in const [50, 100, 200, 500, 1000, 2000])
            Builder(builder: (context) {
              final fee = schedule.feeMinorFor(amount * 100);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Advance of E$amount', style: muted),
                    Text(
                      fee == null ? 'not allowed' : 'fee ${CurrencyFormatter.formatMinor(fee)}',
                      style: muted,
                    ),
                  ],
                ),
              );
            }),
        ],
      ],
    );
  }
}
