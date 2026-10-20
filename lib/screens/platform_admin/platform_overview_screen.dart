import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/platform_overview.dart';
import '../../providers/firebase_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

final platformOverviewProvider = FutureProvider.autoDispose<PlatformOverview>(
  (ref) => ref.watch(platformAdminServiceProvider).platformOverview(),
);

/// Counts across every company, for the platform admin. Deliberately numbers
/// only: who the employees are, and what each of them drew, stays with the
/// employer. The same screen shows the same figures for every company.
class PlatformOverviewScreen extends ConsumerWidget {
  const PlatformOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(platformOverviewProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: const Text('Overview'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(platformOverviewProvider),
          ),
        ],
      ),
      body: GlassBackground(
        child: overview.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$e', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(platformOverviewProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () => ref.refresh(platformOverviewProvider.future),
            child: OverviewBody(overview: data),
          ),
        ),
      ),
    );
  }
}

class OverviewBody extends StatelessWidget {
  final PlatformOverview overview;
  const OverviewBody({super.key, required this.overview});

  @override
  Widget build(BuildContext context) {
    final t = overview.totals;
    final updated = TimeOfDay.fromDateTime(overview.generatedAt).format(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('All companies', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Stat(label: 'Companies', value: '${t.activeCompanies} of ${t.companies}', hint: 'active'),
            _Stat(label: 'Active employees', value: '${t.activeEmployees}'),
            _Stat(label: 'Active workers', value: '${t.activeWorkers}'),
            _Stat(label: 'Advances this cycle', value: '${t.advancesThisCycle}'),
            _Stat(label: 'Waiting for approval', value: '${t.pendingApproval}', warn: t.pendingApproval > 0),
            _Stat(label: 'Waiting to be paid out', value: '${t.awaitingPayout}', warn: t.awaitingPayout > 0),
            _Stat(label: 'Open settlements', value: '${t.openSettlements}'),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Updated $updated. Counts only: no names or individual amounts are shown here.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (overview.truncated)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Only the first ${overview.companies.length} companies are shown.',
              style: TextStyle(color: glassWarning),
            ),
          ),
        const SizedBox(height: 16),
        Text('By company', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (overview.companies.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No companies yet.')),
          ),
        for (final c in overview.companies) _CompanyCard(company: c),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final bool warn;
  const _Stat({required this.label, required this.value, this.hint, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: GlassCard(
        radius: 14,
        showTopGloss: false,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(color: warn ? glassWarning : null),
            ),
            const SizedBox(height: 2),
            Text(hint == null ? label : '$label ($hint)', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  final CompanyOverview company;
  const _CompanyCard({required this.company});

  @override
  Widget build(BuildContext context) {
    final c = company;
    final theme = Theme.of(context);
    Widget cell(String label, String value, {bool warn = false}) => SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: theme.textTheme.titleMedium?.copyWith(color: warn ? glassWarning : null)),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 16,
        showTopGloss: false,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      Text('Code: ${c.shortCode} · ${c.currency}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                GlassChip(
                  label: c.active ? 'Active' : 'Suspended',
                  color: c.active ? glassSuccess : glassDanger,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                cell('Employees', '${c.activeEmployees} of ${c.employees} active'),
                cell('Active workers', '${c.activeWorkers}'),
                cell('Advances this cycle', '${c.advancesThisCycle}'),
                cell('Waiting for approval', '${c.pendingApproval}', warn: c.pendingApproval > 0),
                cell('Waiting to be paid out', '${c.awaitingPayout}', warn: c.awaitingPayout > 0),
                cell(
                  c.openSettlements == 1 ? 'Owed, 1 open settlement' : 'Owed, ${c.openSettlements} open settlements',
                  c.owedDisplay,
                  warn: c.owedMinor > 0,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
