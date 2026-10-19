import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../../models/employee.dart';
import '../../models/fee_schedule.dart';
import '../../models/settings.dart';
import '../../providers/settings_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/theme_providers.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/pay_cycle.dart';
import '../../widgets/glass_components.dart';
import 'fee_schedule_editor.dart';
import 'org_config_screen.dart';
import 'permissions_screen.dart';
import 'rate_matrix_screen.dart';

/// All rules here are configurable without an app update (spec section 7) —
/// they live in the settings/app Firestore document.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(title: const Text('Admin Settings')),
        body: settingsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (settings) => _SettingsForm(settings: settings),
        ),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  final AppSettings settings;
  const _SettingsForm({required this.settings});

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final TextEditingController _companyNameCtrl;
  late double _maxDrawPercent;
  late FeeSchedule _feeSchedule;
  String? _feeProblem;
  late bool _autoApprove;
  late bool _hasCeiling;
  late final TextEditingController _ceilingCtrl;
  late int _maxDrawsPerCycle;
  late ClockSource _clockSource;
  late DisbursementMethod _disbursementPolicy;
  late PaydayRule _paydayRule;

  static const _weekdayNames = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  @override
  void initState() {
    super.initState();
    _companyNameCtrl = TextEditingController(text: widget.settings.companyName);
    _maxDrawPercent = widget.settings.maxDrawPercent;
    _feeSchedule = widget.settings.feeSchedule;
    _autoApprove = widget.settings.autoApprove;
    _hasCeiling = widget.settings.autoApproveMaxMinor != null;
    _ceilingCtrl = TextEditingController(
      text: widget.settings.autoApproveMaxMinor == null
          ? ''
          : (widget.settings.autoApproveMaxMinor! / 100).toStringAsFixed(
              widget.settings.autoApproveMaxMinor! % 100 == 0 ? 0 : 2),
    );
    _maxDrawsPerCycle = widget.settings.maxDrawsPerCycle;
    _clockSource = widget.settings.clockSource;
    _disbursementPolicy = widget.settings.disbursementPolicy;
    _paydayRule = widget.settings.paydayRule;
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _ceilingCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    void refuse(String message) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }

    if (_feeProblem != null) return refuse('Fix the service fee first: $_feeProblem');
    int? ceiling;
    if (_autoApprove && _hasCeiling) {
      ceiling = CurrencyFormatter.parseMinor(_ceilingCtrl.text);
      if (ceiling == null || ceiling <= 0) {
        return refuse('Enter the automatic approval ceiling as an amount, like 200 or 200.00.');
      }
    }
    await ref.read(settingsRepositoryProvider).update(AppSettings(
          companyName: _companyNameCtrl.text.trim(),
          maxDrawPercent: _maxDrawPercent,
          feeSchedule: _feeSchedule,
          maxDrawsPerCycle: _maxDrawsPerCycle,
          clockSource: _clockSource,
          disbursementPolicy: _disbursementPolicy,
          paydayRule: _paydayRule,
          autoApprove: _autoApprove,
          autoApproveMaxMinor: _autoApprove && _hasCeiling ? ceiling : null,
        ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved.')));
    }
  }

  String _paydayRuleLabel(PaydayRule rule) {
    switch (rule.type) {
      case PaydayType.fixedDayOfMonth:
        final suffix = _daySuffix(rule.dayOfMonth);
        return '${rule.dayOfMonth}$suffix of every month';
      case PaydayType.lastDayOfMonth:
        return 'Last day of every month';
      case PaydayType.lastWeekdayOfMonth:
        return 'Last ${_weekdayNames[rule.weekday]} of every month';
    }
  }

  String _daySuffix(int d) {
    if (d >= 11 && d <= 13) return 'th';
    switch (d % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextPayday = PayCycle.nextPayday(_paydayRule);
    final fmt = DateFormat('d MMM yyyy');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Company ────────────────────────────────────────────────────────
        _SectionLabel('Company'),
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(16),
          child: TextFormField(
            controller: _companyNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Company name',
              helperText: 'Shown on the login screen and dashboard',
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Payday schedule ────────────────────────────────────────────────
        _SectionLabel('Payday schedule'),
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type selector
              _PaydayTypeOption(
                label: 'Fixed day of month',
                description: 'e.g. always the 25th',
                selected: _paydayRule.type == PaydayType.fixedDayOfMonth,
                onTap: () => setState(() => _paydayRule =
                    _paydayRule.copyWith(type: PaydayType.fixedDayOfMonth)),
              ),
              const SizedBox(height: 8),
              _PaydayTypeOption(
                label: 'Last day of month',
                description: 'e.g. 28 Feb, 31 Mar, 30 Apr …',
                selected: _paydayRule.type == PaydayType.lastDayOfMonth,
                onTap: () => setState(() => _paydayRule =
                    _paydayRule.copyWith(type: PaydayType.lastDayOfMonth)),
              ),
              const SizedBox(height: 8),
              _PaydayTypeOption(
                label: 'Last weekday of month',
                description: 'e.g. last Friday of every month',
                selected: _paydayRule.type == PaydayType.lastWeekdayOfMonth,
                onTap: () => setState(() => _paydayRule =
                    _paydayRule.copyWith(type: PaydayType.lastWeekdayOfMonth)),
              ),

              // ── Conditional controls ─────────────────────────────────────
              if (_paydayRule.type == PaydayType.fixedDayOfMonth) ...[
                const SizedBox(height: 20),
                Divider(color: context.surfaceTint(0.09)),
                const SizedBox(height: 12),
                Text(
                  'Day of month: ${_paydayRule.dayOfMonth}${_daySuffix(_paydayRule.dayOfMonth)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Slider(
                  value: _paydayRule.dayOfMonth.toDouble(),
                  min: 1,
                  max: 31,
                  divisions: 30,
                  label: '${_paydayRule.dayOfMonth}${_daySuffix(_paydayRule.dayOfMonth)}',
                  onChanged: (v) => setState(() => _paydayRule =
                      _paydayRule.copyWith(dayOfMonth: v.round())),
                ),
                Text(
                  'If the month has fewer days the last day of that month is used.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],

              if (_paydayRule.type == PaydayType.lastWeekdayOfMonth) ...[
                const SizedBox(height: 20),
                Divider(color: context.surfaceTint(0.09)),
                const SizedBox(height: 12),
                Text('Which weekday?',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: List.generate(5, (i) {
                    final wd = i + 1; // 1=Mon … 5=Fri
                    final selected = _paydayRule.weekday == wd;
                    return ChoiceChip(
                      label: Text(_weekdayNames[wd].substring(0, 3)),
                      selected: selected,
                      selectedColor: glassBlue.withValues(alpha: 0.25),
                      backgroundColor: context.surfaceTint(0.06),
                      side: BorderSide(
                        color: selected
                            ? glassBlue.withValues(alpha: 0.60)
                            : context.surfaceTint(0.13),
                      ),
                      labelStyle: TextStyle(
                        color: selected ? glassBlue : context.onSurface(0.75),
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      onSelected: (_) => setState(() =>
                          _paydayRule = _paydayRule.copyWith(weekday: wd)),
                    );
                  }),
                ),
              ],

              // ── Live preview ─────────────────────────────────────────────
              const SizedBox(height: 20),
              Divider(color: context.surfaceTint(0.09)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: glassBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.event_outlined,
                        color: glassBlue, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _paydayRuleLabel(_paydayRule),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Next payday: ${fmt.format(nextPayday)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: glassSuccess,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Draw limits ─────────────────────────────────────────────────────
        _SectionLabel('Draw limits'),
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Max draw: ${(_maxDrawPercent * 100).round()}% of accrued wages',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Slider(
                value: _maxDrawPercent,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                label: '${(_maxDrawPercent * 100).round()}%',
                onChanged: (v) => setState(() => _maxDrawPercent = v),
              ),
              const SizedBox(height: 8),
              Text(
                'Max draws per pay cycle: $_maxDrawsPerCycle',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Slider(
                value: _maxDrawsPerCycle.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '$_maxDrawsPerCycle',
                onChanged: (v) => setState(() => _maxDrawsPerCycle = v.round()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Service fee ─────────────────────────────────────────────────────
        _SectionLabel('Service fee'),
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(16),
          child: FeeScheduleEditor(
            initial: _feeSchedule,
            onChanged: (schedule, problem) {
              _feeSchedule = schedule;
              if (_feeProblem != problem && mounted) {
                setState(() => _feeProblem = problem);
              } else {
                _feeProblem = problem;
              }
            },
          ),
        ),
        const SizedBox(height: 20),

        // ── Automatic approval ──────────────────────────────────────────────
        _SectionLabel('Automatic approval'),
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Approve requests automatically'),
                subtitle: const Text(
                  'A request that passes every limit above is approved without a person. '
                  'Paying it out is still done by your finance team, and every automatic '
                  'approval is recorded in the audit log.',
                ),
                value: _autoApprove,
                onChanged: (v) => setState(() => _autoApprove = v),
              ),
              if (_autoApprove) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Only up to a ceiling'),
                  subtitle: const Text('Larger requests wait for a person to approve them.'),
                  value: _hasCeiling,
                  onChanged: (v) => setState(() => _hasCeiling = v),
                ),
                if (_hasCeiling)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextField(
                      controller: _ceilingCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: const InputDecoration(
                        labelText: 'Approve automatically up to',
                        prefixText: 'E ',
                        helperText: 'The advance amount, before the fee.',
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Operations ──────────────────────────────────────────────────────
        _SectionLabel('Operations'),
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DropdownButtonFormField<ClockSource>(
                initialValue: _clockSource,
                decoration: const InputDecoration(labelText: 'Clock source'),
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: const [
                  DropdownMenuItem(
                      value: ClockSource.manual,
                      child: Text('Manual (in-app button)')),
                  DropdownMenuItem(
                      value: ClockSource.kioskPin, child: Text('Kiosk + PIN')),
                  DropdownMenuItem(
                      value: ClockSource.kioskQr,
                      child: Text('Kiosk + QR / barcode')),
                  DropdownMenuItem(
                      value: ClockSource.externalImport,
                      child: Text('External system import')),
                ],
                onChanged: (v) => setState(() => _clockSource = v!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<DisbursementMethod>(
                initialValue: _disbursementPolicy,
                decoration:
                    const InputDecoration(labelText: 'Disbursement policy'),
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: const [
                  DropdownMenuItem(
                      value: DisbursementMethod.bankTransfer,
                      child: Text('Bank transfer')),
                  DropdownMenuItem(
                      value: DisbursementMethod.mobileMoney,
                      child: Text('Mobile money')),
                  DropdownMenuItem(
                      value: DisbursementMethod.cash,
                      child: Text('Cash / petty cash')),
                ],
                onChanged: (v) => setState(() => _disbursementPolicy = v!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Appearance ───────────────────────────────────────────────────────
        _SectionLabel('Appearance'),
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto_outlined, size: 18),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined, size: 18),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined, size: 18),
                    label: Text('Dark'),
                  ),
                ],
                selected: {ref.watch(themeModeProvider)},
                onSelectionChanged: (v) =>
                    ref.read(themeModeProvider.notifier).state = v.first,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: glassBlue.withValues(alpha: 0.15),
                  selectedForegroundColor: glassBlue,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Organisation & access ────────────────────────────────────────────
        _SectionLabel('Organisation & access'),
        GlassCard(
          radius: 16,
          showTopGloss: false,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _NavTile(
                icon: Icons.corporate_fare,
                label: 'Departments & Roles',
                subtitle: 'Add, remove and reorder departments and roles',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const OrgConfigScreen())),
              ),
              Divider(height: 1, color: context.surfaceTint(0.06)),
              _NavTile(
                icon: Icons.price_change_outlined,
                label: 'Rate Matrix',
                subtitle: 'Standard hourly rates by department and role',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const RateMatrixScreen())),
              ),
              Divider(height: 1, color: context.surfaceTint(0.06)),
              _NavTile(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Permissions',
                subtitle: 'What each role can view, create, edit or delete',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PermissionsScreen())),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        GlassPrimaryButton(
          label: 'Save settings',
          width: double.infinity,
          onPressed: _save,
        ),
      ],
    );
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: context.onSurface(0.45),
            ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: glassBlue, size: 22),
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12, color: context.onSurface(0.45))),
      trailing: Icon(Icons.chevron_right,
          size: 18, color: context.onSurface(0.30)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onTap: onTap,
    );
  }
}

class _PaydayTypeOption extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _PaydayTypeOption({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? glassBlue.withValues(alpha: 0.12)
              : context.surfaceTint(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? glassBlue.withValues(alpha: 0.50)
                : context.surfaceTint(0.10),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? glassBlue : context.onSurface(0.35),
                  width: 2,
                ),
                color: selected ? glassBlue : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : context.onSurface(0.75),
                        ),
                  ),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
