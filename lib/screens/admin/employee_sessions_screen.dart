import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/employee.dart';
import '../../models/time_session.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/time_session_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';
import 'hours_edit_dialog.dart';

/// Per-employee punch history — drill-down from the Workforce screen.
/// Lets admin see individual clock-in/out records (not just the aggregate
/// accrued balance), review/clear flags raised by the buddy-punching checks
/// (spec section 6), and, when the company allows it, add missing hours or
/// correct and void records. Every manual change needs a reason and is logged.
class EmployeeSessionsScreen extends ConsumerWidget {
  final Employee employee;

  const EmployeeSessionsScreen({super.key, required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(employeeSessionsProvider(employee.id));
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final canEdit = settings?.allowManualHourEdits ?? true;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(
          title: Text('${employee.name} · punches'),
          actions: [
            if (canEdit)
              IconButton(
                tooltip: 'Add missing hours',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _add(context, ref, settings?.maxShiftHours ?? 14),
              ),
          ],
        ),
        body: sessions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: Text(canEdit ? 'No punches recorded yet. Use + to add hours.' : 'No punches recorded yet.'),
              );
            }
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => _SessionTile(
                session: list[i],
                canEdit: canEdit,
                maxShiftHours: settings?.maxShiftHours ?? 14,
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, int maxShiftHours) async {
    final edit = await showHoursEditDialog(context, title: 'Add missing hours', maxShiftHours: maxShiftHours);
    if (edit == null || !context.mounted) return;
    await _run(context, 'Hours added.', () => ref.read(timeSessionRepositoryProvider).addHours(
          employeeId: employee.id,
          clockIn: edit.clockIn,
          clockOut: edit.clockOut,
          reason: edit.reason,
          editorId: FirebaseAuth.instance.currentUser!.uid,
        ));
  }
}

Future<void> _run(BuildContext context, String done, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } on FirebaseException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.code == 'permission-denied'
          ? 'Not allowed. Check that Admin Settings still allow manual hour changes.'
          : 'Could not save: ${e.message}'),
    ));
  }
}

class _SessionTile extends ConsumerWidget {
  final TimeSession session;
  final bool canEdit;
  final int maxShiftHours;

  const _SessionTile({required this.session, required this.canEdit, required this.maxShiftHours});

  String _fmtDateTime(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDuration(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  String get _origin => switch (session.source) {
        ClockEventSource.adminEdit => 'entered by an admin',
        ClockEventSource.externalImport => 'uploaded',
        _ => session.source.name,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(timeSessionRepositoryProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GlassCard(
        radius: 12,
        showTopGloss: false,
        surfaceColor: session.flagged ? glassDanger.withValues(alpha: 0.08) : null,
        child: ListTile(
          leading: session.photoUrl != null
              ? CircleAvatar(backgroundImage: NetworkImage(session.photoUrl!))
              : const CircleAvatar(child: Icon(Icons.access_time)),
          title: Text(
            _fmtDateTime(session.clockIn),
            style: session.voided ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
          ),
          subtitle: Text(
            '${session.voided ? "VOIDED · " : ""}'
            '${session.clockOut != null ? "out ${_fmtDateTime(session.clockOut!)} · ${_fmtDuration(session.hoursWorked)}" : "still clocked in"}'
            ' · $_origin'
            '${session.isReviewed ? ' · reviewed' : ''}'
            '${session.editReason != null ? '\nReason: ${session.editReason}' : ''}',
          ),
          isThreeLine: session.editReason != null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  session.flagged ? Icons.flag : Icons.outlined_flag,
                  color: session.flagged ? glassDanger : null,
                ),
                tooltip: session.flagged ? 'Clear flag' : 'Flag for review',
                onPressed: () => repo.flag(session.id, !session.flagged),
              ),
              if (canEdit && !session.voided)
                PopupMenuButton<String>(
                  tooltip: 'Edit or void',
                  onSelected: (choice) async {
                    if (choice == 'edit') {
                      final edit = await showHoursEditDialog(
                        context,
                        title: 'Correct hours',
                        maxShiftHours: maxShiftHours,
                        initialIn: session.clockIn,
                        initialOut: session.clockOut,
                      );
                      if (edit == null || !context.mounted) return;
                      await _run(context, 'Record corrected.', () => repo.editHours(
                            session: session,
                            clockIn: edit.clockIn,
                            clockOut: edit.clockOut,
                            reason: edit.reason,
                            editorId: uid,
                          ));
                    } else {
                      final reason = await askReason(context, title: 'Void this record?', action: 'Void');
                      if (reason == null || !context.mounted) return;
                      await _run(context, 'Record voided.', () => repo.voidHours(session: session, reason: reason, editorId: uid));
                    }
                  },
                  itemBuilder: (_) => [
                    if (session.clockOut != null) const PopupMenuItem(value: 'edit', child: Text('Correct the times')),
                    const PopupMenuItem(value: 'void', child: Text('Void this record')),
                  ],
                ),
            ],
          ),
          onTap: session.photoUrl == null
              ? null
              : () => showDialog(
                    context: context,
                    builder: (_) => Dialog(child: Image.network(session.photoUrl!)),
                  ),
        ),
      ),
    );
  }
}
