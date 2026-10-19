import '../../brand.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/company.dart';
import '../../models/employee.dart';
import '../../models/org_config.dart';
import '../../providers/auth_providers.dart';
import '../../providers/company_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/theme_providers.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../widgets/glass_components.dart';

class WorkerProfileScreen extends ConsumerWidget {
  final Employee employee;
  const WorkerProfileScreen({super.key, required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyId = ref.watch(myCompanyIdProvider);
    final company = companyId == null
        ? null
        : ref.watch(companyByIdProvider(companyId)).valueOrNull;
    final companyName = ref.watch(myCompanyNameProvider);

    final initials = employee.name
        .trim()
        .split(' ')
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    final disbursementLabel = switch (employee.disbursementMethod) {
      DisbursementMethod.bankTransfer =>
        '${employee.disbursementDetails['bankName'] ?? 'Bank transfer'}'
            '${employee.disbursementDetails['accountNumber'] != null ? ' · ****${employee.disbursementDetails['accountNumber']!.split('').reversed.take(4).toList().reversed.join()}' : ''}',
      DisbursementMethod.mobileMoney =>
        '${employee.disbursementDetails['provider'] ?? 'Mobile money'}'
            '${employee.disbursementDetails['phoneNumber'] != null ? ' · ${employee.disbursementDetails['phoneNumber']}' : ''}',
      DisbursementMethod.cash => 'Cash / petty cash',
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glassBlue.withOpacity(0.15),
                  border: Border.all(
                      color: glassBlue.withOpacity(0.30), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: glassBlue.withOpacity(0.20),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: context.onSurface(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(employee.name,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              if (employee.department.isNotEmpty)
                Text(
                  employee.department,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.onSurface(0.55),
                      ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _SectionHeader('Employment'),
        if (companyName.isNotEmpty)
          _InfoTile(
            icon: Icons.business_outlined,
            label: 'Company',
            value: companyName,
          ),
        if (employee.employeeNumber.isNotEmpty)
          _InfoTile(
            icon: Icons.numbers_outlined,
            label: 'Employee number',
            value: employee.employeeNumber,
          ),
        if (employee.department.isNotEmpty)
          _InfoTile(
            icon: Icons.corporate_fare_outlined,
            label: 'Department',
            value: employee.department,
          ),
        _InfoTile(
          icon: Icons.badge_outlined,
          label: 'Role',
          value: roleLabel(employee.role),
        ),
        _InfoTile(
          icon: Icons.payments_outlined,
          label: 'Hourly rate',
          value: '${CurrencyFormatter.format(employee.hourlyRate)} / hr',
        ),
        _InfoTile(
          icon: Icons.account_balance_outlined,
          label: 'Disbursement',
          value: disbursementLabel,
        ),
        const SizedBox(height: 20),
        _SectionHeader('Account'),
        _InfoTile(
          icon: Icons.email_outlined,
          label: 'Email',
          value: FirebaseAuth.instance.currentUser?.email ?? '—',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassCard(
            radius: 14,
            showTopGloss: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.brightness_6_outlined),
                  const SizedBox(width: 12),
                  Text('Theme',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const Spacer(),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 16),
                      ),
                    ],
                    selected: {ref.watch(themeModeProvider)},
                    onSelectionChanged: (v) =>
                        ref.read(themeModeProvider.notifier).state = v.first,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: glassBlue.withValues(alpha: 0.15),
                      selectedForegroundColor: glassBlue,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    showSelectedIcon: false,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        GlassCard(
          radius: 14,
          showTopGloss: false,
          child: ListTile(
            leading: const Icon(Icons.lock_outlined),
            title: const Text('Change password'),
            trailing:
                const Icon(Icons.chevron_right, size: 18),
            onTap: () => _showChangePasswordSheet(context, ref),
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeader('Help & info'),
        GlassCard(
          radius: 14,
          showTopGloss: false,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('How ${Brand.name} works'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _showHowItWorks(context, ref, company),
              ),
              if (company != null && company.hrEmail.isNotEmpty) ...[
                Divider(height: 1, indent: 56, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.email_outlined, color: glassBlue),
                  title: const Text('Email HR'),
                  subtitle: Text(company.hrEmail),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => launchUrl(Uri.parse('mailto:${company.hrEmail}')),
                ),
              ],
              if (company != null && company.hrPhone.isNotEmpty) ...[
                Divider(height: 1, indent: 56, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.phone_outlined, color: glassBlue),
                  title: const Text('Call HR'),
                  subtitle: Text(company.hrPhone),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => launchUrl(
                      Uri.parse('tel:${company.hrPhone.replaceAll(' ', '')}')),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: glassDanger,
            side: const BorderSide(color: glassDanger),
            minimumSize: const Size(double.infinity, 48),
          ),
          onPressed: () => ref.read(authServiceProvider).signOut(),
        ),
      ],
    );
  }

  void _showHowItWorks(BuildContext context, WidgetRef ref, Company? company) {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    final pct = settings != null
        ? '${(settings.maxDrawPercent * 100).toStringAsFixed(0)}%'
        : '50%';
    final drawsPerCycle = settings?.maxDrawsPerCycle ?? 2;
    final contactParts = [
      if (company != null && company.hrEmail.isNotEmpty) company.hrEmail,
      if (company != null && company.hrPhone.isNotEmpty) company.hrPhone,
    ];
    final contactLine = contactParts.isEmpty
        ? 'For questions or help, contact your HR or admin team.'
        : 'For questions or help, contact HR at:\n${contactParts.join(' · ')}';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('How ${Brand.name} works'),
        content: SingleChildScrollView(
          child: Text(
            '${Brand.name} lets you access a portion of the wages you have '
            'already earned, before your scheduled payday.\n\n'
            '• You can request up to $pct of your accrued wages per pay cycle.\n'
            '• Up to $drawsPerCycle advance${drawsPerCycle == 1 ? '' : 's'} allowed per cycle.\n'
            '• A small service fee applies — shown before you confirm.\n'
            '• The advance + fee is automatically deducted from your next payslip.\n'
            '• Requests are reviewed and approved by your HR or admin team.\n'
            '• Your employer\'s finance team sends the money and marks it as paid.\n\n'
            '$contactLine',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ChangePasswordSheet(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        radius: 14,
        showTopGloss: false,
        child: ListTile(
          leading: Icon(icon),
          title: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: context.onSurface(0.60))),
          subtitle: Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_newCtrl.text.length < 6) {
      setState(() => _error = 'New password must be at least 6 characters.');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final auth = ref.read(authServiceProvider);
      final email = FirebaseAuth.instance.currentUser?.email ?? '';
      await auth.reauthenticate(email, _currentCtrl.text);
      await auth.changePassword(_newCtrl.text);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.code == 'wrong-password'
          ? 'Current password is incorrect.'
          : 'Failed to update password. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change password',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          TextField(
            controller: _currentCtrl,
            decoration: const InputDecoration(
              labelText: 'Current password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newCtrl,
            decoration: const InputDecoration(
              labelText: 'New password',
              border: OutlineInputBorder(),
              helperText: 'Minimum 6 characters',
            ),
            obscureText: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Update password'),
            ),
          ),
        ],
      ),
    );
  }
}
