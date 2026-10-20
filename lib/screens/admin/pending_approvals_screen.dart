import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/draw_request.dart';
import '../../providers/draw_providers.dart';
import '../../providers/employee_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/glass_components.dart';

class PendingApprovalsScreen extends ConsumerWidget {
  const PendingApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount =
        ref.watch(pendingDrawsProvider).valueOrNull?.length ?? 0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(
          title: const Text('Approvals'),
          bottom: TabBar(
            indicatorColor: glassBlue,
            labelColor: glassBlue,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            dividerColor: context.surfaceTint(0.07),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pending'),
                    if (pendingCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: glassBlue.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$pendingCount',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Tab(text: 'History'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PendingTab(),
            _HistoryTab(),
          ],
        ),
      ),
    );
  }
}

// ── Pending tab ───────────────────────────────────────────────────────────────

class _PendingTab extends ConsumerWidget {
  const _PendingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingDrawsProvider);
    return pending.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const _FriendlyError(
          message: 'Could not load requests.\nPlease try again.'),
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text('All caught up!',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'No pending draw requests.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(pendingDrawsProvider);
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: requests.length,
            itemBuilder: (_, i) => _ApprovalCard(request: requests[i]),
          ),
        );
      },
    );
  }
}

// ── History tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab();

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(drawHistoryProvider);
    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const _FriendlyError(
          message: 'Could not load history.\nPlease try again.'),
      data: (requests) {
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text('No decisions yet',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Approved and rejected requests will appear here.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        final filtered = _filter == 'all'
            ? requests
            : requests
                .where((r) => r.status.name == _filter)
                .toList();
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(drawHistoryProvider);
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'approved', label: Text('Approved')),
                    ButtonSegment(value: 'rejected', label: Text('Rejected')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (v) =>
                      setState(() => _filter = v.first),
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: glassBlue.withValues(alpha: 0.15),
                    selectedForegroundColor: glassBlue,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) =>
                      _HistoryCard(request: filtered[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Pending approval card ─────────────────────────────────────────────────────

class _ApprovalCard extends ConsumerStatefulWidget {
  final DrawRequest request;
  const _ApprovalCard({required this.request});

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _loading = false;

  Future<void> _decide(bool approve, {String? reason}) async {
    setState(() => _loading = true);
    try {
      final firstOfTwo = await ref
          .read(drawRepositoryProvider)
          .decide(requestId: widget.request.id, approve: approve, reason: reason);
      if (firstOfTwo && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your approval is recorded. A different admin must give the second approval.')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not record that. Please try again.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRejectDialog() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Optionally provide a reason — the employee will see this.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                hintText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: glassDanger),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final reason = reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim();
      await _decide(false, reason: reason);
    }
    reasonCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final employee =
        ref.watch(employeeByIdProvider(widget.request.employeeId)).valueOrNull;
    final name = employee?.name ?? '…';
    final dept = employee?.department ?? '';
    final role = employee?.role ?? '';

    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();
    final dateFmt = DateFormat('d MMM · HH:mm');

    final roleColor = switch (role) {
      'supervisor' => glassWarning,
      'admin' => const Color(0xFFAB7AFF),
      _ => glassBlue,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: roleColor.withValues(alpha: 0.15),
                    border: Border.all(
                        color: roleColor.withValues(alpha: 0.30), width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        [
                          if (dept.isNotEmpty) dept,
                          dateFmt.format(widget.request.createdAt.toLocal()),
                          if (widget.request.firstApprovalBy != null)
                            'first approval given, needs a second admin'
                          else if (widget.request.needsSecondApproval)
                            'needs two admins',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.onSurface(0.55),
                            ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.format(widget.request.amount),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'requested',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: context.onSurface(0.40),
                          ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            GlassCard(
              radius: 10,
              showTopGloss: false,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _DetailItem(
                      label: 'Advance',
                      value: CurrencyFormatter.format(widget.request.amount)),
                  const _Divider(),
                  _DetailItem(
                      label: 'Fee',
                      value: CurrencyFormatter.format(widget.request.fee)),
                  const _Divider(),
                  _DetailItem(
                      label: 'Total deducted',
                      value: CurrencyFormatter.format(widget.request.total),
                      highlight: true),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: glassDanger,
                        side: const BorderSide(color: glassDanger),
                      ),
                      onPressed: _showRejectDialog,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                      onPressed: () => _decide(true),  // no reason for approvals
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ── History card ──────────────────────────────────────────────────────────────

class _HistoryCard extends ConsumerWidget {
  final DrawRequest request;
  const _HistoryCard({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employee =
        ref.watch(employeeByIdProvider(request.employeeId)).valueOrNull;
    final name = employee?.name ?? '…';
    final dept = employee?.department ?? '';
    final role = employee?.role ?? '';

    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

    final isApproved = request.status == DrawStatus.approved;
    final statusColor = isApproved ? glassSuccess : glassDanger;
    final statusLabel = isApproved ? 'Approved' : 'Rejected';
    final statusIcon =
        isApproved ? Icons.check_circle_outline : Icons.cancel_outlined;

    final roleColor = switch (role) {
      'supervisor' => glassWarning,
      'admin' => const Color(0xFFAB7AFF),
      _ => glassBlue,
    };

    final requestFmt = DateFormat('d MMM yyyy');
    final decidedFmt = DateFormat('d MMM · HH:mm');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: roleColor.withValues(alpha: 0.15),
                    border: Border.all(
                        color: roleColor.withValues(alpha: 0.30), width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        [
                          if (dept.isNotEmpty) dept,
                          'Requested ${requestFmt.format(request.createdAt.toLocal())}',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.onSurface(0.55),
                            ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.format(request.amount),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'advance',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: context.onSurface(0.40),
                          ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: context.surfaceTint(0.07), height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.30), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (request.decidedAt != null)
                  Text(
                    decidedFmt.format(request.decidedAt!.toLocal()),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.onSurface(0.40),
                        ),
                  ),
              ],
            ),
            if (!isApproved && request.reason != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 13, color: glassDanger.withValues(alpha: 0.65)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      request.reason!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: glassDanger.withValues(alpha: 0.80),
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _FriendlyError extends StatelessWidget {
  final String message;
  const _FriendlyError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _DetailItem(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.onSurface(0.45),
                  )),
          Text(value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: highlight ? glassWarning : null,
                  )),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: context.surfaceTint(0.08),
    );
  }
}
