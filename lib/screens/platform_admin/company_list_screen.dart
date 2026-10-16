import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/company.dart';
import '../../providers/company_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';
import 'create_company_screen.dart';

/// Platform-admin company directory: every company (active or suspended),
/// with a suspend/reactivate toggle. Deliberately does not link anywhere
/// into a company's employees/draws/payroll/audit data.
class CompanyListScreen extends ConsumerWidget {
  const CompanyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companiesAsync = ref.watch(allCompaniesProvider);

    return companiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load companies: $e')),
      data: (companies) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      companies.isEmpty
                          ? 'No companies yet.'
                          : '${companies.length} compan${companies.length == 1 ? 'y' : 'ies'}',
                      style: TextStyle(color: context.onSurface(0.60)),
                    ),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add company'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreateCompanyScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: companies.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Create the first company to get started.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.onSurface(0.55)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: companies.length,
                      itemBuilder: (context, i) => _CompanyTile(company: companies[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CompanyTile extends ConsumerWidget {
  final Company company;
  const _CompanyTile({required this.company});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        radius: 16,
        showTopGloss: false,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(company.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('Code: ${company.shortCode} · ${company.currency}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassChip(
                label: company.active ? 'Active' : 'Suspended',
                color: company.active ? glassSuccess : glassDanger,
              ),
              const SizedBox(width: 8),
              Switch(
                value: company.active,
                onChanged: (v) => _confirmToggle(context, ref, v),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmToggle(BuildContext context, WidgetRef ref, bool active) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(active ? 'Reactivate company?' : 'Suspend company?'),
        content: Text(
          active
              ? '${company.name} can claim new seats again.'
              : '${company.name} will no longer be listed for new employees to '
                  'claim a seat. Existing employees keep their access — this does '
                  'not disable any current logins. Existing data is preserved.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(active ? 'Reactivate' : 'Suspend'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(companyRepositoryProvider).setActive(company.id, active);
  }
}
