import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/employee.dart';
import '../../models/org_config.dart';
import '../../providers/employee_providers.dart';
import '../../providers/org_config_providers.dart';
import '../../providers/time_session_providers.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/glass_components.dart';
import 'employee_form_screen.dart';
import 'employee_sessions_screen.dart';

class WorkforceOverviewScreen extends ConsumerStatefulWidget {
  const WorkforceOverviewScreen({super.key});

  @override
  ConsumerState<WorkforceOverviewScreen> createState() =>
      _WorkforceOverviewScreenState();
}

class _WorkforceOverviewScreenState
    extends ConsumerState<WorkforceOverviewScreen> {
  String _query = '';

  Future<void> _refresh() async {
    ref.invalidate(allEmployeesProvider);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(allEmployeesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Workforce')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add employee'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EmployeeFormScreen()),
        ),
      ),
      body: employees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
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
                  'Could not load employees.\nPlease try again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.group_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('No employees yet.'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Add first employee'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const EmployeeFormScreen()),
                    ),
                  ),
                ],
              ),
            );
          }

          final orgConfig =
              ref.watch(orgConfigProvider).valueOrNull ?? OrgConfig.defaults();

          final rolesInData = list.map((e) => e.role).toSet();
          final orderedRoles = [
            ...orgConfig.roles.where(rolesInData.contains),
            ...rolesInData.where(
                (r) => !orgConfig.roles.contains(r) && r != 'admin'),
            if (rolesInData.contains('admin')) 'admin',
          ];

          final filtered = _query.isEmpty
              ? list
              : list
                  .where((e) =>
                      e.name
                          .toLowerCase()
                          .contains(_query.toLowerCase()) ||
                      e.department
                          .toLowerCase()
                          .contains(_query.toLowerCase()))
                  .toList();

          final sections = orderedRoles
              .map((role) => (
                    role: role,
                    employees:
                        filtered.where((e) => e.role == role).toList()
                  ))
              .where((s) => s.employees.isNotEmpty)
              .toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by name or department…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() => _query = ''),
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                if (filtered.isEmpty && _query.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No results for "$_query"',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  )
                else
                  for (int i = 0; i < sections.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _SectionHeader(
                      label: roleLabel(sections[i].role),
                      count: sections[i].employees.length,
                    ),
                    ...sections[i]
                        .employees
                        .map((e) => _EmployeeTile(employee: e)),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Text(
        '$label ($count)',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

String _fmtHours(Duration d) {
  final h = d.inMinutes ~/ 60;
  final m = d.inMinutes % 60;
  if (h == 0 && m == 0) return '0h';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class _EmployeeTile extends ConsumerWidget {
  final Employee employee;
  const _EmployeeTile({required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showStats =
        employee.role == 'worker' || employee.role == 'supervisor';
    final accrued =
        showStats ? ref.watch(accruedWagesProvider(employee.id)) : 0.0;
    final hoursWorked =
        showStats ? ref.watch(hoursWorkedProvider(employee.id)) : Duration.zero;

    final initials = employee.name
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    final roleColor = switch (employee.role) {
      'admin' => const Color(0xFFAB7AFF),
      'worker' => glassBlue,
      'supervisor' => glassWarning,
      _ => glassBlue,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        radius: 12,
        showTopGloss: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EmployeeFormScreen(employee: employee),
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: roleColor.withValues(alpha: 0.15),
                      border: Border.all(
                          color: roleColor.withValues(alpha: 0.30), width: 1.5),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: context.onSurface(),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                employee.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (employee.role != 'worker') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: roleColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: roleColor.withValues(alpha: 0.25),
                                      width: 0.8),
                                ),
                                child: Text(
                                  roleLabel(employee.role),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: roleColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),

                        // Department · rate
                        Text(
                          [
                            if (employee.employeeNumber.isNotEmpty)
                              employee.employeeNumber,
                            if (employee.department.isNotEmpty)
                              employee.department,
                            'E ${employee.hourlyRate.toStringAsFixed(2)}/hr',
                          ].join(' · '),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: context.onSurface(0.60),
                                  ),
                        ),

                        // Hours + accrued (workers & supervisors)
                        if (showStats) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.schedule,
                                  size: 12, color: context.onSurface(0.40)),
                              const SizedBox(width: 3),
                              Text(
                                _fmtHours(hoursWorked),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: context.onSurface(0.60)),
                              ),
                              Text(' · ',
                                  style: TextStyle(
                                      color: context.onSurface(0.25))),
                              Text(
                                '${CurrencyFormatter.format(accrued)} accrued',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: accrued > 0
                                          ? glassBlue
                                          : context.onSurface(0.60),
                                      fontWeight: accrued > 0
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                              ),
                            ],
                          ),
                        ],

                        // Status chips
                        if (employee.mustChangePassword) ...[
                          const SizedBox(height: 4),
                          GlassChip(
                            label: 'Awaiting password change',
                            color: glassWarning,
                          ),
                        ],
                        if (employee.consentedAt == null) ...[
                          const SizedBox(height: 4),
                          GlassChip(
                            label: 'Consent pending',
                            color: glassBlue,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Actions
                  IconButton(
                    icon: const Icon(Icons.history_outlined),
                    tooltip: 'View punches',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            EmployeeSessionsScreen(employee: employee),
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_outlined, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
