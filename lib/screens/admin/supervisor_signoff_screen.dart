import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/signoff_record.dart';
import '../../providers/signoff_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';
import '../../widgets/sign_out_button.dart';

/// Daily sign-off of hours (spec section 6, buddy-punching mitigations). Used by supervisors
/// and admins. The list comes from the server with employees' names, so a supervisor needs
/// no access to employee records. Nobody can sign off their own hours or a record they
/// typed in or uploaded themselves; those rows show a lock and wait for someone else.
class SupervisorSignoffScreen extends ConsumerStatefulWidget {
  /// Shown as the supervisor's home screen, with a sign-out button.
  final bool isHome;
  const SupervisorSignoffScreen({super.key, this.isHome = false});

  @override
  ConsumerState<SupervisorSignoffScreen> createState() => _SupervisorSignoffScreenState();
}

class _SupervisorSignoffScreenState extends ConsumerState<SupervisorSignoffScreen> {
  DateTime _selectedDay = DateTime.now();
  bool _busy = false;

  DateTime get _day => DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDay = picked);
  }

  Future<void> _signOffDay(List<SignOffRecord> records) async {
    final mine = records.where((r) => r.needsSignOff && r.canSign).toList();
    if (mine.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign off day?'),
        content: Text(
          'Signs off ${mine.length} record${mine.length == 1 ? '' : 's'} on ${_formatDay(_selectedDay)}. '
          'Hours you cannot sign yourself (your own, or ones you entered) are left for someone else.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign off')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(signOffServiceProvider).signOff([for (final r in mine) r.id]);
      ref.invalidate(signOffDayProvider(_day));
      messenger.showSnackBar(SnackBar(
        content: Text('Signed off ${result.signed}.${result.refused.isEmpty ? '' : ' ${result.refused.length} could not be signed.'}'),
      ));
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'Could not sign off. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _formatDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(signOffDayProvider(_day));

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(
          title: Text('Sign-off · ${_formatDay(_selectedDay)}'),
          automaticallyImplyLeading: !widget.isHome,
          actions: [
            IconButton(tooltip: 'Choose a day', icon: const Icon(Icons.calendar_today), onPressed: _pickDay),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(signOffDayProvider(_day))),
            if (widget.isHome) const SignOutButton(),
          ],
        ),
        floatingActionButton: recordsAsync.maybeWhen(
          data: (records) => records.any((r) => r.needsSignOff && r.canSign)
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(_busy ? 'Signing…' : 'Sign off day'),
                  onPressed: _busy ? null : () => _signOffDay(records),
                )
              : null,
          orElse: () => null,
        ),
        body: recordsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(e is FirebaseFunctionsException ? (e.message ?? 'Could not load.') : 'Could not load this day. Pull to refresh.'),
            ),
          ),
          data: (records) {
            if (records.isEmpty) return const Center(child: Text('No punches on this day.'));
            // Flagged first, then those still waiting, then the rest.
            final sorted = [...records]
              ..sort((a, b) {
                if (a.flagged != b.flagged) return a.flagged ? -1 : 1;
                if (a.needsSignOff != b.needsSignOff) return a.needsSignOff ? -1 : 1;
                return b.clockIn.compareTo(a.clockIn);
              });
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: sorted.length,
              itemBuilder: (context, i) => _PunchTile(record: sorted[i]),
            );
          },
        ),
      ),
    );
  }
}

class _PunchTile extends StatelessWidget {
  final SignOffRecord record;
  const _PunchTile({required this.record});

  String _time(DateTime t) =>
      '${t.toLocal().hour.toString().padLeft(2, '0')}:${t.toLocal().minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final r = record;
    final name = r.employeeName.isEmpty ? r.employeeId : r.employeeName;
    final origin = switch (r.source) {
      'adminEdit' => 'entered by an admin',
      'externalImport' => 'uploaded',
      _ => r.source,
    };
    final status = r.voided
        ? const Icon(Icons.block, color: glassDanger)
        : r.flagged
            ? const Icon(Icons.flag, color: glassDanger)
            : r.reviewed
                ? const Icon(Icons.check_circle, color: glassSuccess)
                : r.canSign
                    ? const Icon(Icons.hourglass_empty)
                    : const Tooltip(
                        message: 'Someone else must sign this off',
                        child: Icon(Icons.lock_outline),
                      );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GlassCard(
        radius: 12,
        showTopGloss: false,
        surfaceColor: r.flagged ? glassDanger.withValues(alpha: 0.08) : null,
        child: ListTile(
          leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
          title: Text(
            r.employeeNumber.isEmpty ? name : '$name · ${r.employeeNumber}',
            style: r.voided ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
          ),
          subtitle: Text(
            '${_time(r.clockIn)}${r.clockOut != null ? ' – ${_time(r.clockOut!)}' : ' (still clocked in)'}'
            ' · $origin${r.reviewed ? ' · signed off' : ''}${r.voided ? ' · void' : ''}'
            '${r.editReason != null ? '\nReason: ${r.editReason}' : ''}',
          ),
          isThreeLine: r.editReason != null,
          trailing: status,
        ),
      ),
    );
  }
}
