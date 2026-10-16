import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/time_session.dart';
import '../../providers/employee_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/time_session_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

/// Supervisor daily sign-off (spec section 6, buddy-punching mitigations):
/// a quick review/approval of a day's punches before they lock in. Flagged
/// punches (suspiciously back-to-back clock-ins) are surfaced first.
class SupervisorSignoffScreen extends ConsumerStatefulWidget {
  const SupervisorSignoffScreen({super.key});

  @override
  ConsumerState<SupervisorSignoffScreen> createState() => _SupervisorSignoffScreenState();
}

class _SupervisorSignoffScreenState extends ConsumerState<SupervisorSignoffScreen> {
  DateTime _selectedDay = DateTime.now();

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDay = picked);
  }

  Future<void> _signOffDay(List<TimeSession> sessions) async {
    final reviewerId = ref.read(authServiceProvider).currentUser?.uid;
    if (reviewerId == null) return;
    final unreviewed = sessions.where((s) => !s.isReviewed).toList();
    if (unreviewed.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign off day?'),
        content: Text(
          'Marks all ${unreviewed.length} unreviewed punch(es) on '
          '${_formatDay(_selectedDay)} as reviewed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign off')),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(timeSessionRepositoryProvider)
        .markReviewedBatch(unreviewed, reviewerId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day signed off.')),
      );
    }
  }

  static String _formatDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsForDayProvider(_selectedDay));

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(
          title: Text('Sign-off · ${_formatDay(_selectedDay)}'),
          actions: [
            IconButton(icon: const Icon(Icons.calendar_today), onPressed: _pickDay),
          ],
        ),
        floatingActionButton: sessionsAsync.maybeWhen(
          data: (sessions) => sessions.isEmpty
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Sign off day'),
                  onPressed: () => _signOffDay(sessions),
                ),
          orElse: () => null,
        ),
        body: sessionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (sessions) {
            if (sessions.isEmpty) {
              return const Center(child: Text('No punches on this day.'));
            }
            // Flagged punches surface first for quicker review.
            final sorted = [...sessions]
              ..sort((a, b) {
                if (a.flagged != b.flagged) return a.flagged ? -1 : 1;
                return b.clockIn.compareTo(a.clockIn);
              });
            return ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (context, i) => _PunchTile(session: sorted[i]),
            );
          },
        ),
      ),
    );
  }
}

class _PunchTile extends ConsumerWidget {
  final TimeSession session;

  const _PunchTile({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee = ref.watch(employeeByIdProvider(session.employeeId)).valueOrNull;
    final timeFmt = (DateTime t) =>
        '${t.toLocal().hour.toString().padLeft(2, '0')}:${t.toLocal().minute.toString().padLeft(2, '0')}';

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
              : CircleAvatar(
                  child: Text(
                      (employee?.name ?? '?')[0].toUpperCase())),
          title: Text(employee?.name ?? session.employeeId),
          subtitle: Text(
            '${timeFmt(session.clockIn)}'
            '${session.clockOut != null ? ' – ${timeFmt(session.clockOut!)}' : ' (still clocked in)'}'
            ' · ${session.source.name}'
            '${session.isReviewed ? ' · reviewed' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (session.flagged)
                const Icon(Icons.flag, color: glassDanger)
              else if (session.isReviewed)
                const Icon(Icons.check_circle, color: glassSuccess)
              else
                const Icon(Icons.hourglass_empty,
                    color: Color(0x80FFFFFF)),
              IconButton(
                icon: Icon(
                    session.flagged ? Icons.flag : Icons.outlined_flag),
                tooltip:
                    session.flagged ? 'Clear flag' : 'Flag for review',
                onPressed: () => ref
                    .read(timeSessionRepositoryProvider)
                    .flag(session.id, !session.flagged),
              ),
            ],
          ),
          onTap: session.photoUrl == null
              ? null
              : () => showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      child: Image.network(session.photoUrl!),
                    ),
                  ),
        ),
      ),
    );
  }
}
