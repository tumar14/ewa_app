import '../../widgets/sign_out_button.dart';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/employee.dart';
import '../../providers/auth_providers.dart';
import '../../providers/draw_providers.dart';
import '../../providers/employee_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/time_session_providers.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/glass_components.dart';
import 'employee_form_screen.dart';
import 'settings_screen.dart';
import 'supervisor_signoff_screen.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(pendingDrawsCountProvider);
    final disburseCount = ref.watch(pendingDisbursementCountProvider);
    final flaggedCount =
        ref.watch(flaggedTodayCountProvider).valueOrNull ?? 0;
    final employees = ref.watch(allEmployeesProvider).valueOrNull ?? [];
    final pendingDraws = ref.watch(pendingDrawsProvider).valueOrNull ?? [];
    final totalRequested =
        pendingDraws.fold<double>(0, (s, d) => s + d.amount);
    final companyName =
        ref.watch(appSettingsProvider).valueOrNull?.companyName ?? '';
    final adminName = ref.watch(currentEmployeeProvider).valueOrNull?.name ?? '';
    final firstName = adminName.trim().split(' ').first;

    final now = DateTime.now();
    final greetingBase = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final greeting =
        firstName.isNotEmpty ? '$greetingBase, $firstName' : greetingBase;
    final dateStr = DateFormat('EEEE, d MMMM').format(now);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: const Text('Dashboard'),
        actions: [
          const SignOutButton(),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add employee',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EmployeeFormScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Greeting card
          GlassCard(
            radius: 20,
            surfaceColor: const Color(0x1A14B8A6),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  companyName.isNotEmpty ? companyName : 'Dashboard',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  style: TextStyle(
                      color: context.onSurface(0.50), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stat cards
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.fact_check_outlined,
                  label: 'Pending approvals',
                  value: '$pendingCount',
                  color: pendingCount > 0 ? Colors.orange : Colors.green,
                  subtitle: pendingCount > 0
                      ? '${CurrencyFormatter.format(totalRequested)} total'
                      : 'All clear',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.send_to_mobile_outlined,
                  label: 'Awaiting disburse',
                  value: '$disburseCount',
                  color: disburseCount > 0 ? Colors.blue : Colors.green,
                  subtitle: disburseCount > 0 ? 'Action needed' : 'All sent',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatCard(
            icon: Icons.groups_outlined,
            label: 'Active employees',
            value: '${employees.length}',
            color: cs.primary,
            subtitle:
                '${employees.where((e) => e.role == 'worker').length} workers'
                ' · ${employees.where((e) => e.role == 'admin').length} admins',
            wide: true,
          ),
          if (flaggedCount > 0) ...[
            const SizedBox(height: 12),
            GlassCard(
              radius: 16,
              surfaceColor: glassWarning.withValues(alpha: 0.10),
              padding: const EdgeInsets.all(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SupervisorSignoffScreen()),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: glassWarning.withValues(alpha: 0.15),
                      ),
                      child: const Icon(Icons.rule_outlined,
                          color: glassWarning, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$flaggedCount flagged punch${flaggedCount == 1 ? '' : 'es'} today',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: glassWarning),
                          ),
                          Text(
                            'Tap to review in Supervisor Sign-off',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: context.onSurface(0.55)),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: glassWarning),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          Text('Quick actions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.person_add_outlined,
                  label: 'Add employee',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const EmployeeFormScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.science_outlined,
                    label: 'Seed test data',
                    onTap: () => _showSeedDialog(context, ref),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showSeedDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _SeedDialog(parentRef: ref),
    );
  }
}

// ---------------------------------------------------------------------------
// Seed dialog — creates realistic test workers + an extra admin in one tap
// ---------------------------------------------------------------------------

class _SeedDialog extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  const _SeedDialog({required this.parentRef});

  @override
  ConsumerState<_SeedDialog> createState() => _SeedDialogState();
}

class _SeedDialogState extends ConsumerState<_SeedDialog> {
  bool _running = false;
  String _status = '';

  // Generated fresh per seed run rather than a fixed literal — this is a
  // debug-only dev tool (kDebugMode-gated), but a hardcoded credential in
  // source is bad practice regardless.
  static const _passwordAlphabet =
      'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  final String _temporaryPassword = List.generate(
    10,
    (_) => _passwordAlphabet[Random.secure().nextInt(_passwordAlphabet.length)],
  ).join();

  static const _workers = [
    {
      'name': 'Sipho Dlamini',
      'email': 'sipho.dlamini@ftmswaziland.com',
      'hourlyRate': 22.50,
      'pin': '1111',
      'method': 'mobileMoney',
      'phone': '+268 7601 1111',
      'provider': 'MTN',
    },
    {
      'name': 'Nothando Mthembu',
      'email': 'nothando.m@ftmswaziland.com',
      'hourlyRate': 18.00,
      'pin': '2222',
      'method': 'cash',
    },
    {
      'name': 'Bongani Nkosi',
      'email': 'bongani.nkosi@ftmswaziland.com',
      'hourlyRate': 25.00,
      'pin': '3333',
      'method': 'bankTransfer',
      'bank': 'FNB Eswatini',
      'account': '62001234567',
    },
    {
      'name': 'Zanele Shabalala',
      'email': 'zanele.shabalala@ftmswaziland.com',
      'hourlyRate': 20.00,
      'pin': '4444',
      'method': 'mobileMoney',
      'phone': '+268 7604 4444',
      'provider': 'E-Mali',
    },
    {
      'name': 'Thembi Simelane',
      'email': 'thembi.simelane@ftmswaziland.com',
      'hourlyRate': 21.00,
      'pin': '5555',
      'method': 'cash',
    },
  ];

  static const _extraAdmin = {
    'name': 'HR Manager',
    'email': 'hr.manager@ftmswaziland.com',
    'hourlyRate': 0.0,
    'pin': '',
    'method': 'cash',
    'role': 'admin',
  };

  Future<void> _seed() async {
    setState(() {
      _running = true;
      _status = 'Starting…';
    });

    final repo = ref.read(employeeRepositoryProvider);
    final allTasks = [..._workers, _extraAdmin];
    int done = 0;
    final errors = <String>[];

    for (final w in allTasks) {
      final name = w['name'] as String;
      setState(() => _status = 'Creating $name…');
      try {
        final method = DisbursementMethod.values.firstWhere(
          (m) => m.name == (w['method'] as String),
          orElse: () => DisbursementMethod.cash,
        );

        final details = <String, String>{};
        if (method == DisbursementMethod.bankTransfer) {
          if (w['bank'] != null) details['bankName'] = w['bank'] as String;
          if (w['account'] != null) details['accountNumber'] = w['account'] as String;
        } else if (method == DisbursementMethod.mobileMoney) {
          if (w['phone'] != null) details['phoneNumber'] = w['phone'] as String;
          if (w['provider'] != null) details['provider'] = w['provider'] as String;
        }

        await repo.create(
          name: name,
          email: w['email'] as String,
          temporaryPassword: _temporaryPassword,
          hourlyRate: (w['hourlyRate'] as num).toDouble(),
          employeeNumber: (w['empNum'] as String?) ?? '',
          role: (w['role'] as String?) ?? 'worker',
          pin: (w['pin'] as String?)?.isNotEmpty == true
              ? w['pin'] as String
              : null,
          disbursementMethod: method,
          disbursementDetails: details,
        );
        done++;
      } catch (e) {
        // Email already exists → skip silently (idempotent)
        final msg = e.toString();
        if (!msg.contains('email-already-in-use')) {
          errors.add('$name: $msg');
        } else {
          done++;
        }
      }
    }

    setState(() {
      _running = false;
      _status = errors.isEmpty
          ? '$done accounts ready. Password for all: $_temporaryPassword'
          : '${errors.length} error(s):\n${errors.join('\n')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seed test data'),
      content: SizedBox(
        width: 320,
        child: _running || _status.isNotEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_running) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_status),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This will create the following accounts '
                      '(skipped if they already exist):'),
                  const SizedBox(height: 12),
                  for (final w in _workers)
                    Text('• ${w['name']} — E${(w['hourlyRate'] as num).toStringAsFixed(0)}/hr · PIN ${w['pin']}'),
                  Text('• ${_extraAdmin['name']} — admin'),
                  const SizedBox(height: 12),
                  Text('Password for all: $_temporaryPassword',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
      ),
      actions: _running
          ? null
          : [
              if (_status.isEmpty)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              if (_status.isEmpty)
                FilledButton(
                  onPressed: _seed,
                  child: const Text('Create all'),
                ),
              if (_status.isNotEmpty)
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
            ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card widgets
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String subtitle;
  final bool wide;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.subtitle,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: wide
            ? Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.12),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style:
                                Theme.of(context).textTheme.labelMedium),
                        Text(value,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(subtitle,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.12),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(label,
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                ],
              ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionCard(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: glassBlue),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: glassBlue),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
