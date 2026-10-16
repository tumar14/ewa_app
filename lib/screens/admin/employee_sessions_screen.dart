import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/employee.dart';
import '../../models/time_session.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/time_session_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

/// Per-employee punch history — drill-down from the Workforce screen.
/// Lets admin see individual clock-in/out records (not just the aggregate
/// accrued balance) and review/clear flags raised by the buddy-punching
/// checks (spec section 6).
class EmployeeSessionsScreen extends ConsumerWidget {
  final Employee employee;

  const EmployeeSessionsScreen({super.key, required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(employeeSessionsProvider(employee.id));
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(title: Text('${employee.name} · punches')),
        body: sessions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) {
            if (list.isEmpty) return const Center(child: Text('No punches recorded yet.'));
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) => _SessionTile(session: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final TimeSession session;

  const _SessionTile({required this.session});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GlassCard(
        radius: 12,
        showTopGloss: false,
        surfaceColor: session.flagged
            ? glassDanger.withOpacity(0.08)
            : null,
        child: ListTile(
          leading: session.photoUrl != null
              ? CircleAvatar(
                  backgroundImage: NetworkImage(session.photoUrl!))
              : const CircleAvatar(child: Icon(Icons.access_time)),
          title: Text(_fmtDateTime(session.clockIn)),
          subtitle: Text(
            '${session.clockOut != null ? "out ${_fmtDateTime(session.clockOut!)} · ${_fmtDuration(session.hoursWorked)}" : "still clocked in"}'
            ' · ${session.source.name}'
            '${session.isReviewed ? ' · reviewed' : ''}',
          ),
          trailing: IconButton(
            icon: Icon(
              session.flagged ? Icons.flag : Icons.outlined_flag,
              color: session.flagged ? glassDanger : null,
            ),
            tooltip: session.flagged ? 'Clear flag' : 'Flag for review',
            onPressed: () => ref
                .read(timeSessionRepositoryProvider)
                .flag(session.id, !session.flagged),
          ),
          onTap: session.photoUrl == null
              ? null
              : () => showDialog(
                    context: context,
                    builder: (_) =>
                        Dialog(child: Image.network(session.photoUrl!)),
                  ),
        ),
      ),
    );
  }
}
