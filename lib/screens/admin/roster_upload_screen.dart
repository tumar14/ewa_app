import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/roster_entry.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/org_config_providers.dart';
import '../../providers/roster_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

/// Admin screen for employee-first onboarding: pre-load employee records so
/// workers can claim their own accounts. Supports pasting CSV rows and adding
/// rows one at a time. Claimed rows are read-only (they link to a live login).
class RosterUploadScreen extends ConsumerWidget {
  const RosterUploadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosterAsync = ref.watch(rosterProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: const Text('Employee Roster'),
        actions: [
          IconButton(
            tooltip: 'Import CSV',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => _showImportSheet(context, ref),
          ),
        ],
      ),
      body: GlassBackground(
        child: rosterAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load roster: $e')),
          data: (entries) {
            final unclaimed = entries.where((e) => !e.claimed).length;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entries.isEmpty
                              ? 'No employees loaded yet.'
                              : '${entries.length} loaded · $unclaimed awaiting claim',
                          style: TextStyle(color: context.onSurface(0.60)),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                        onPressed: () => _showEntrySheet(context, ref),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? _EmptyState(onImport: () => _showImportSheet(context, ref))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: entries.length,
                          itemBuilder: (context, i) =>
                              _RosterTile(entry: entries[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showEntrySheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEntrySheet(),
    );
  }

  void _showImportSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImportSheet(),
    );
  }
}

class _RosterTile extends ConsumerWidget {
  final RosterEntry entry;
  const _RosterTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        radius: 16,
        showTopGloss: false,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(entry.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${entry.employeeNumber} · E ${entry.hourlyRate.toStringAsFixed(2)}/hr'
            '${entry.department.isNotEmpty ? ' · ${entry.department}' : ''}',
          ),
          trailing: entry.claimed
              ? const GlassChip(label: 'Claimed', color: glassSuccess)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _copyCode(context, entry.claimCode),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.key_outlined,
                              size: 14, color: context.onSurface(0.45)),
                          const SizedBox(width: 3),
                          Text(entry.claimCode,
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  color: context.onSurface(0.70))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _confirmDelete(context, ref),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Claim code $code copied')),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove roster entry?'),
        content: Text(
            '${entry.name} (${entry.employeeNumber}) will be removed and can '
            'no longer claim an account until re-added.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(rosterRepositoryProvider).delete(entry.employeeNumber);
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onImport;
  const _EmptyState({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined,
                size: 64, color: context.onSurface(0.30)),
            const SizedBox(height: 16),
            Text('Load your workforce',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: context.onSurface(0.80))),
            const SizedBox(height: 8),
            Text(
              'Add employees here so they can download the app and claim their '
              'own accounts with their employee number and name.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.onSurface(0.55)),
            ),
            const SizedBox(height: 20),
            GlassPrimaryButton(
                label: 'Import CSV', icon: Icons.upload_file, onPressed: onImport),
          ],
        ),
      ),
    );
  }
}

/// Manual single-employee add.
class _AddEntrySheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends ConsumerState<_AddEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _empNumCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _claimCodeCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _empNumCtrl, _nameCtrl, _rateCtrl, _deptCtrl, _claimCodeCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final code = await ref.read(rosterRepositoryProvider).upsert(RosterEntry(
            employeeNumber: _empNumCtrl.text.trim(),
            name: _nameCtrl.text.trim(),
            hourlyRate: double.parse(_rateCtrl.text.trim()),
            department: _deptCtrl.text.trim(),
            claimCode: _claimCodeCtrl.text.trim(),
          ));
      if (mounted) {
        Navigator.of(context).pop();
        _showCode(context, _nameCtrl.text.trim(), code);
      }
    } catch (e) {
      setState(() => _error = e is StateError ? e.message : 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showCode(BuildContext context, String name, String code) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Claim code'),
        content: Text(
          'Give this code to $name — they\'ll need it, along with their '
          'employee number and name, to claim their account:\n\n$code',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(ctx);
            },
            child: const Text('Copy & close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgConfig = ref.watch(orgConfigProvider).valueOrNull;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: GlassCard(
        radius: 24,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add employee to roster',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _empNumCtrl,
                decoration: const InputDecoration(
                    labelText: 'Employee number', hintText: 'e.g. EMP-001'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Full name'),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rateCtrl,
                decoration: const InputDecoration(
                    labelText: 'Hourly rate (SZL)', prefixText: 'E '),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) return 'Enter a number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                controller: _deptCtrl,
                enableFilter: true,
                requestFocusOnTap: true,
                expandedInsets: EdgeInsets.zero,
                label: const Text('Department'),
                dropdownMenuEntries: (orgConfig?.departments ?? [])
                    .map((d) => DropdownMenuEntry(value: d, label: d))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _claimCodeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Claim code (optional)',
                  helperText: 'Leave blank to auto-generate a one-time code',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              GlassPrimaryButton(
                label: _saving ? '' : 'Add to roster',
                loading: _saving,
                width: double.infinity,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paste-CSV bulk import. Columns: employeeNumber, name, hourlyRate, department.
class _ImportSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  final _csvCtrl = TextEditingController();
  bool _saving = false;
  String? _error;
  String? _result;

  @override
  void dispose() {
    _csvCtrl.dispose();
    super.dispose();
  }

  /// Parses CSV text into roster entries. Tolerates a header row and blank
  /// lines. Returns the entries and a list of human-readable row errors.
  ({List<RosterEntry> entries, List<String> errors}) _parse(String text) {
    final entries = <RosterEntry>[];
    final errors = <String>[];
    final lines = const LineSplitter().convert(text);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cells = line.split(',').map((c) => c.trim()).toList();
      // Skip a header row.
      if (i == 0 &&
          cells.first.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') ==
              'employeenumber') {
        continue;
      }
      if (cells.length < 3) {
        errors.add('Line ${i + 1}: needs at least employee number, name, rate');
        continue;
      }
      final rate = double.tryParse(cells[2]);
      if (cells[0].isEmpty || cells[1].isEmpty || rate == null) {
        errors.add('Line ${i + 1}: invalid employee number, name or rate');
        continue;
      }
      entries.add(RosterEntry(
        employeeNumber: cells[0],
        name: cells[1],
        hourlyRate: rate,
        department: cells.length > 3 ? cells[3] : '',
        claimCode: cells.length > 4 ? cells[4] : '',
      ));
    }
    return (entries: entries, errors: errors);
  }

  Future<void> _import() async {
    setState(() {
      _saving = true;
      _error = null;
      _result = null;
    });
    final parsed = _parse(_csvCtrl.text);
    if (parsed.entries.isEmpty) {
      setState(() {
        _saving = false;
        _error = parsed.errors.isEmpty
            ? 'Nothing to import.'
            : parsed.errors.join('\n');
      });
      return;
    }
    try {
      final res = await ref.read(rosterRepositoryProvider).bulkUpsert(parsed.entries);
      final parts = <String>['Imported ${res.written} employee(s).'];
      if (res.codes.isNotEmpty) {
        final codeLines = res.codes.entries
            .map((e) => '${e.key}: ${e.value}')
            .join('\n');
        parts.add('Claim codes — give each to the matching employee:\n$codeLines');
      }
      if (res.skipped.isNotEmpty) {
        parts.add('Skipped ${res.skipped.length} already-claimed: '
            '${res.skipped.join(', ')}');
      }
      if (parsed.errors.isNotEmpty) {
        parts.add('${parsed.errors.length} line(s) had errors:\n'
            '${parsed.errors.join('\n')}');
      }
      setState(() => _result = parts.join('\n\n'));
    } catch (e) {
      setState(() => _error = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: GlassCard(
        radius: 24,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Import roster from CSV',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'One employee per line: employee number, name, hourly rate, '
              'department (optional), claim code (optional — auto-generated '
              'if left blank). A header row is ignored.',
              style: TextStyle(color: context.onSurface(0.55), fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _csvCtrl,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'EMP-001, Thabo Dlamini, 45.00, Sewing\n'
                    'EMP-002, Nomsa Nkambule, 52.50, Cutting',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error, fontSize: 13)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(_result!,
                  style: const TextStyle(color: glassSuccess, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            GlassPrimaryButton(
              label: _saving ? '' : (_result != null ? 'Done' : 'Import'),
              loading: _saving,
              width: double.infinity,
              onPressed: _saving
                  ? null
                  : (_result != null ? () => Navigator.of(context).pop() : _import),
            ),
          ],
        ),
      ),
    );
  }
}
