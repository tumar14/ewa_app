import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/draw_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';
import 'admin_dashboard_screen.dart';
import 'audit_log_screen.dart';
import 'disbursements_screen.dart';
import 'payroll_export_screen.dart';
import 'pending_approvals_screen.dart';
import 'org_config_screen.dart';
import 'permissions_screen.dart';
import 'rate_matrix_screen.dart';
import 'roster_upload_screen.dart';
import 'settlements_screen.dart';
import 'transactions_screen.dart';
import 'settings_screen.dart';
import 'supervisor_signoff_screen.dart';
import 'workforce_overview_screen.dart';

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _index = 0;

  static const _screens = [
    AdminDashboardScreen(),
    PendingApprovalsScreen(),
    WorkforceOverviewScreen(),
    DisbursementsScreen(),
    _MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(pendingDrawsCountProvider);
    final disburseCount = ref.watch(pendingDisbursementCountProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(child: _screens[_index]),
      bottomNavigationBar: GlassNavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.fact_check_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.fact_check),
            ),
            label: 'Approvals',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Workforce',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: disburseCount > 0,
              label: Text('$disburseCount'),
              child: const Icon(Icons.send_to_mobile_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: disburseCount > 0,
              label: Text('$disburseCount'),
              child: const Icon(Icons.send_to_mobile),
            ),
            label: 'Disburse',
          ),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _MoreScreen extends ConsumerWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MoreTile(
            icon: Icons.rule_outlined,
            label: 'Supervisor Sign-off',
            subtitle: 'Review and sign off attendance exceptions',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SupervisorSignoffScreen())),
          ),
          _MoreTile(
            icon: Icons.receipt_long_outlined,
            label: 'Transactions',
            subtitle: 'Every advance: status, amount and fee',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const TransactionsScreen())),
          ),
          _MoreTile(
            icon: Icons.payments_outlined,
            label: 'Payroll Export',
            subtitle: 'Generate and export payroll runs',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PayrollExportScreen())),
          ),
          _MoreTile(
            icon: Icons.account_balance_outlined,
            label: 'Settlements',
            subtitle: 'Track what employers remit for deducted draws',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SettlementsScreen())),
          ),
          _MoreTile(
            icon: Icons.history_outlined,
            label: 'Audit Log',
            subtitle: 'Full activity and decision history',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AuditLogScreen())),
          ),
          _MoreTile(
            icon: Icons.badge_outlined,
            label: 'Employee Roster',
            subtitle: 'Pre-load employees so they can claim their own accounts',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const RosterUploadScreen())),
          ),
          _MoreTile(
            icon: Icons.corporate_fare,
            label: 'Departments & Roles',
            subtitle: 'Add, remove and reorder departments and roles',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const OrgConfigScreen())),
          ),
          _MoreTile(
            icon: Icons.price_change_outlined,
            label: 'Rate Matrix',
            subtitle: 'Standard hourly rates by department and role',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const RateMatrixScreen())),
          ),
          _MoreTile(
            icon: Icons.admin_panel_settings_outlined,
            label: 'Permissions',
            subtitle: 'Configure what each role can view and do',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PermissionsScreen())),
          ),
          _MoreTile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            subtitle: 'Draw caps, fees, payday schedule',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.logout, color: glassDanger),
            title: const Text('Sign out',
                style: TextStyle(color: glassDanger)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        radius: 16,
        showTopGloss: false,
        child: ListTile(
          leading: Icon(icon, color: glassBlue),
          title: Text(label),
          subtitle: Text(subtitle),
          trailing:
              const Icon(Icons.chevron_right, size: 18),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          onTap: onTap,
        ),
      ),
    );
  }
}
