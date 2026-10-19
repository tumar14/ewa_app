import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/draw_request.dart';
import '../../models/employee.dart';
import '../../models/settings.dart';
import '../../models/time_session.dart';
import '../../providers/auth_providers.dart';
import '../../providers/draw_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/time_session_providers.dart';
import '../../theme/glass_theme.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/pay_cycle.dart';
import '../../utils/wage_calculator.dart';
import '../../widgets/glass_components.dart';
import '../../widgets/skeleton.dart';
import '../clocking/clocking_screen.dart';
import 'worker_profile_screen.dart';

class WorkerHomeScreen extends ConsumerStatefulWidget {
  final String employeeId;
  const WorkerHomeScreen({super.key, required this.employeeId});

  @override
  ConsumerState<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends ConsumerState<WorkerHomeScreen> {
  int _index = 0;

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final employee = ref.watch(currentEmployeeProvider).valueOrNull;
    final firstName = employee?.name.trim().split(' ').first ?? '';

    final appSettings = ref.watch(appSettingsProvider).valueOrNull;
    final isKiosk = appSettings != null &&
        (appSettings.clockSource == ClockSource.kioskPin ||
            appSettings.clockSource == ClockSource.kioskQr);

    if (isKiosk) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: GlassBackground(
          child: Column(
            children: [
              GlassAppBar(
                title: const Text('Kiosk — Clock In / Out'),
                automaticallyImplyLeading: false,
              ),
              Expanded(child: ClockingBody(employeeId: widget.employeeId)),
            ],
          ),
        ),
      );
    }

    final titles = [
      '${_greeting()}, $firstName',
      'Clock In / Out',
      'My Profile',
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(titles[_index])),
      body: GlassBackground(
        child: IndexedStack(
          index: _index,
          children: [
            _HomeTab(employeeId: widget.employeeId),
            ClockingBody(employeeId: widget.employeeId),
            employee == null
                ? const Center(child: CircularProgressIndicator())
                : WorkerProfileScreen(employee: employee),
          ],
        ),
      ),
      bottomNavigationBar: GlassNavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.access_time_outlined),
            selectedIcon: Icon(Icons.access_time_filled),
            label: 'Clock',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ── Home tab ───────────────────────────────────────────────────────────────────

class _HomeTab extends ConsumerStatefulWidget {
  final String employeeId;
  const _HomeTab({required this.employeeId});

  @override
  ConsumerState<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<_HomeTab> {
  Future<void> _refresh() async {
    ref.invalidate(employeeDrawsProvider(widget.employeeId));
    ref.invalidate(cycleSessionsProvider(widget.employeeId));
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HomeHero(employeeId: widget.employeeId),
          const SizedBox(height: 16),
          _ActiveDrawTimeline(employeeId: widget.employeeId),
          _RecentAdvancesSection(employeeId: widget.employeeId),
          const SizedBox(height: 8),
          _MiniHoursSection(employeeId: widget.employeeId),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Merged hero: accrual + pay cycle + CTA ────────────────────────────────────

class _HomeHero extends ConsumerWidget {
  final String employeeId;
  const _HomeHero({required this.employeeId});

  void _showDrawSheet(
      BuildContext context, double maxAdditional, double feePercent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DrawRequestSheet(
        employeeId: employeeId,
        maxAmount: maxAdditional,
        feePercent: feePercent,
      ),
    );
  }

  static String _fmtHours(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String _blockedReason(
      double accrued, List<DrawRequest> draws, bool canRequest, AppSettings settings) {
    if (accrued <= 0) return 'No wages accrued yet — clock in to start earning.';
    if (draws.any((d) => d.status == DrawStatus.pending)) {
      return 'Your advance request is awaiting approval.';
    }
    if (!canRequest) {
      final n = settings.maxDrawsPerCycle;
      return 'You\'ve used all $n advance${n == 1 ? '' : 's'} for this cycle.';
    }
    return 'No additional wages available to advance this cycle.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final accrued = ref.watch(accruedWagesProvider(employeeId));
    final hoursWorked = ref.watch(hoursWorkedProvider(employeeId));
    final openSession = ref.watch(openSessionProvider(employeeId));
    final draws =
        ref.watch(outstandingDrawsProvider(employeeId)).valueOrNull ?? [];
    final isClockedIn = openSession.valueOrNull != null;

    final now = DateTime.now();
    final rule = settings?.paydayRule ?? const PaydayRule();
    final cycleStart = PayCycle.currentCycleStart(rule);
    final payday = PayCycle.nextPayday(rule);
    final today = DateTime(now.year, now.month, now.day);
    final daysToPayday = payday.difference(today).inDays;
    final totalCycleDays = payday.difference(cycleStart).inDays;
    final elapsedDays =
        today.difference(cycleStart).inDays.clamp(0, totalCycleDays);
    final cycleProgress =
        totalCycleDays > 0 ? elapsedDays / totalCycleDays : 0.0;

    final activeDraws =
        draws.where((d) => d.status != DrawStatus.rejected).toList();
    final alreadyDrawn = WageCalculator.alreadyDrawn(activeDraws);
    final totalFees = activeDraws.fold<double>(0, (s, d) => s + d.fee);
    final estimatedNet =
        (accrued - alreadyDrawn - totalFees).clamp(0.0, double.infinity);
    final maxAdditional = WageCalculator.maxAdditionalDraw(
      accrued: accrued,
      maxDrawPercent: settings?.maxDrawPercent ?? 0.5,
      cycleDraws: activeDraws,
    );
    final canRequest = WageCalculator.canRequestDraw(
      cycleDraws: activeDraws,
      maxDrawsPerCycle: settings?.maxDrawsPerCycle ?? 2,
    );

    final dateFmt = DateFormat('d MMM');
    final paydayFmt = DateFormat('EEE d MMM');

    return GlassCard(
      radius: 20,
      surfaceColor: const Color(0x1A14B8A6),
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Accrual amount ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Earned this cycle',
                      style: TextStyle(
                        color: context.onSurface(0.65),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    if (isClockedIn)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: glassSuccess.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: glassSuccess.withValues(alpha: 0.40),
                              width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: glassSuccess,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'LIVE',
                              style: TextStyle(
                                color: glassSuccess,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  CurrencyFormatter.format(accrued),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: context.onSurface(),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.schedule_outlined,
                        size: 13, color: context.onSurface(0.50)),
                    const SizedBox(width: 4),
                    Text(
                      '${_fmtHours(hoursWorked)} logged',
                      style: TextStyle(
                          color: context.onSurface(0.50), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Request advance CTA ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text(
                  canRequest && maxAdditional > 0
                      ? 'Request advance · ${CurrencyFormatter.format(maxAdditional)} avail.'
                      : 'Request advance',
                ),
                onPressed: (canRequest && maxAdditional > 0 && settings != null)
                    ? () => _showDrawSheet(
                        context, maxAdditional, settings.feePercent)
                    : null,
              ),
            ),
          ),
          if (settings != null && !(canRequest && maxAdditional > 0))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                _blockedReason(accrued, draws, canRequest, settings),
                style: TextStyle(fontSize: 12, color: context.onSurface(0.55)),
                textAlign: TextAlign.center,
              ),
            ),

          const SizedBox(height: 16),

          // ── Pay cycle progress ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${dateFmt.format(cycleStart)} – ${dateFmt.format(payday)}',
                      style: TextStyle(
                          fontSize: 12, color: context.onSurface(0.55)),
                    ),
                    const Spacer(),
                    Text(
                      daysToPayday == 0
                          ? 'Payday today!'
                          : '$daysToPayday day${daysToPayday == 1 ? '' : 's'} to payday',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: daysToPayday <= 3
                            ? glassWarning
                            : context.onSurface(0.65),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: cycleProgress,
                    minHeight: 6,
                    backgroundColor: context.surfaceTint(0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      daysToPayday <= 3 ? glassWarning : glassBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Payday ${paydayFmt.format(payday)}',
                  style: TextStyle(
                      fontSize: 11, color: context.onSurface(0.40)),
                ),
              ],
            ),
          ),

          // ── Pay breakdown ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Divider(color: context.surfaceTint(0.08), height: 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: [
                _HeroStat(
                  label: 'Accrued',
                  value: CurrencyFormatter.format(accrued),
                  color: context.onSurface(),
                ),
                _HeroStat(
                  label: 'Advanced',
                  value: alreadyDrawn > 0
                      ? '−${CurrencyFormatter.format(alreadyDrawn + totalFees)}'
                      : '—',
                  color: alreadyDrawn > 0
                      ? glassDanger
                      : context.onSurface(0.30),
                ),
                _HeroStat(
                  label: 'Take-home est.',
                  value: CurrencyFormatter.format(estimatedNet),
                  color: glassSuccess,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _HeroStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Draw request sheet (modal) ─────────────────────────────────────────────────

class _DrawRequestSheet extends ConsumerStatefulWidget {
  final String employeeId;
  final double maxAmount;
  final double feePercent;
  const _DrawRequestSheet({
    required this.employeeId,
    required this.maxAmount,
    required this.feePercent,
  });

  @override
  ConsumerState<_DrawRequestSheet> createState() => _DrawRequestSheetState();
}

class _DrawRequestSheetState extends ConsumerState<_DrawRequestSheet> {
  double _amount = 0;
  final _textCtrl = TextEditingController();
  bool _confirming = false;
  bool _submitting = false;
  bool _succeeded = false;
  String? _error;

  static const _chipAmounts = [50.0, 100.0, 250.0];

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textCtrl.removeListener(_onTextChanged);
    _textCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final val = double.tryParse(_textCtrl.text) ?? 0;
    final clamped = val.clamp(0.0, widget.maxAmount);
    if (clamped != _amount) setState(() => _amount = clamped);
  }

  void _setAmount(double v) {
    final clamped = v.clamp(0.0, widget.maxAmount);
    setState(() => _amount = clamped);
    _textCtrl.removeListener(_onTextChanged);
    _textCtrl.text = clamped == 0 ? '' : clamped.toStringAsFixed(0);
    _textCtrl.addListener(_onTextChanged);
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(drawRepositoryProvider)
          .requestDraw(CurrencyFormatter.toMinor(_amount));
      if (mounted) setState(() => _succeeded = true);
    } on FirebaseFunctionsException catch (e) {
      final detail = e.code == 'failed-precondition' ||
              e.code == 'invalid-argument' ||
              e.code == 'permission-denied'
          ? e.message
          : null;
      if (mounted) {
        setState(() => _error =
            detail ?? 'Could not submit. Please try again or contact HR.');
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'Could not submit. Please try again or contact HR.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = WageCalculator.feeFor(_amount, widget.feePercent);
    final total = _amount + fee;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: _succeeded
          ? _SuccessContent(
              amount: _amount,
              onDone: () => Navigator.of(context).pop(),
            )
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _confirming
                  ? _ConfirmStep(
                      key: const ValueKey('confirm'),
                      amount: _amount,
                      fee: fee,
                      total: total,
                      submitting: _submitting,
                      error: _error,
                      onBack: () => setState(() => _confirming = false),
                      onConfirm: _submit,
                    )
                  : _SelectStep(
                      key: const ValueKey('select'),
                      amount: _amount,
                      maxAmount: widget.maxAmount,
                      feePercent: widget.feePercent,
                      chipAmounts: _chipAmounts,
                      textCtrl: _textCtrl,
                      onAmountChanged: _setAmount,
                      onReview: _amount > 0
                          ? () => setState(() => _confirming = true)
                          : null,
                    ),
            ),
    );
  }
}

class _SelectStep extends StatelessWidget {
  final double amount;
  final double maxAmount;
  final double feePercent;
  final List<double> chipAmounts;
  final TextEditingController textCtrl;
  final ValueChanged<double> onAmountChanged;
  final VoidCallback? onReview;

  const _SelectStep({
    super.key,
    required this.amount,
    required this.maxAmount,
    required this.feePercent,
    required this.chipAmounts,
    required this.textCtrl,
    required this.onAmountChanged,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final fee = WageCalculator.feeFor(amount, feePercent);
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Request an advance',
            style: Theme.of(context).textTheme.titleLarge),
        Text(
          'Available: ${CurrencyFormatter.format(maxAmount)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),

        // Quick amount chips
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ...chipAmounts
                .where((v) => v <= maxAmount)
                .map((v) => FilterChip(
                      label: Text('E${v.toInt()}'),
                      selected: amount == v,
                      onSelected: (_) => onAmountChanged(v),
                    )),
            FilterChip(
              label: const Text('Max'),
              selected: amount == maxAmount,
              onSelected: (_) => onAmountChanged(maxAmount),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Slider + numeric input row
        Row(
          children: [
            Expanded(
              child: Slider(
                value: amount.clamp(0, maxAmount),
                max: maxAmount,
                divisions: maxAmount > 0
                    ? (maxAmount / 10).clamp(5, 100).toInt()
                    : 1,
                onChanged: onAmountChanged,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                controller: textCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  prefixText: 'E',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),

        // Fee preview
        if (amount > 0) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Service fee (${(feePercent * 100).toStringAsFixed(0)}%)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                CurrencyFormatter.format(fee),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onReview,
            child: const Text('Review request'),
          ),
        ),
      ],
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  final double amount;
  final double fee;
  final double total;
  final bool submitting;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  const _ConfirmStep({
    super.key,
    required this.amount,
    required this.fee,
    required this.total,
    required this.submitting,
    this.error,
    required this.onBack,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Confirm request',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),

        // Summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _SummaryRow(
                label: 'You receive',
                value: CurrencyFormatter.format(amount),
                valueColor: glassSuccess,
              ),
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Service fee',
                value: '+ ${CurrencyFormatter.format(fee)}',
                valueColor: cs.onSurfaceVariant,
              ),
              Divider(height: 20, color: cs.outlineVariant),
              _SummaryRow(
                label: 'Deducted at payday',
                value: CurrencyFormatter.format(total),
                valueColor: glassWarning,
                bold: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'This amount will be deducted from your next payslip.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!,
              style: TextStyle(color: cs.error, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            OutlinedButton(
              onPressed: submitting ? null : onBack,
              child: const Text('Edit'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: submitting ? null : onConfirm,
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Confirm & submit'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool bold;
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
        ),
      ],
    );
  }
}

// ── Draw lifecycle timeline ────────────────────────────────────────────────────

class _ActiveDrawTimeline extends ConsumerWidget {
  final String employeeId;
  const _ActiveDrawTimeline({required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draws = ref.watch(employeeDrawsProvider(employeeId));
    return draws.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(height: 16, width: 120, radius: 6),
          const SizedBox(height: 10),
          GlassCard(
            radius: 16,
            showTopGloss: false,
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Skeleton(height: 14, radius: 6),
              const SizedBox(height: 10),
              Skeleton(height: 10, radius: 6),
              const SizedBox(height: 6),
              Skeleton(height: 10, width: 180, radius: 6),
            ]),
          ),
          const SizedBox(height: 16),
        ],
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final recent = list.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latest advance',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _DrawTimelineCard(draw: recent),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _DrawTimelineCard extends StatelessWidget {
  final DrawRequest draw;
  const _DrawTimelineCard({required this.draw});

  static final _dateFmt = DateFormat('d MMM · HH:mm');

  Color _statusColor(DrawStatus s) => switch (s) {
        DrawStatus.pending => glassWarning,
        DrawStatus.approved => glassSuccess,
        DrawStatus.rejected => glassDanger,
      };

  String _statusLabel(DrawStatus s, DisbursementStatus? disb) {
    if (s == DrawStatus.pending) return 'Pending';
    if (s == DrawStatus.rejected) return 'Rejected';
    if (disb == DisbursementStatus.completed) return 'Sent';
    return 'Approved';
  }

  @override
  Widget build(BuildContext context) {
    final isRejected = draw.status == DrawStatus.rejected;

    final steps = isRejected
        ? [
            _TStep(
              icon: Icons.send_outlined,
              label: 'Submitted',
              sublabel: _dateFmt.format(draw.createdAt.toLocal()),
              done: true,
              color: glassBlue,
            ),
            _TStep(
              icon: Icons.cancel_outlined,
              label: 'Rejected',
              sublabel: draw.reason ??
                  (draw.decidedAt != null
                      ? _dateFmt.format(draw.decidedAt!.toLocal())
                      : null),
              done: true,
              color: glassDanger,
            ),
          ]
        : [
            _TStep(
              icon: Icons.send_outlined,
              label: 'Submitted',
              sublabel: _dateFmt.format(draw.createdAt.toLocal()),
              done: true,
              color: glassBlue,
            ),
            _TStep(
              icon: Icons.check_circle_outline,
              label: 'Approved',
              sublabel: draw.decidedAt != null
                  ? _dateFmt.format(draw.decidedAt!.toLocal())
                  : null,
              done: draw.status == DrawStatus.approved,
              color: glassSuccess,
            ),
            _TStep(
              icon: Icons.mobile_screen_share_outlined,
              label: 'Paid by employer',
              sublabel: draw.disbursedAt != null
                  ? _dateFmt.format(draw.disbursedAt!.toLocal())
                  : null,
              done: draw.disbursementStatus == DisbursementStatus.completed,
              color: const Color(0xFFAB7AFF),
            ),
            _TStep(
              icon: Icons.receipt_long_outlined,
              label: 'Deducted at payday',
              sublabel: null,
              done: draw.payrollRunId != null,
              color: glassWarning,
            ),
          ];

    final statusColor = _statusColor(draw.status);

    return GlassCard(
      radius: 16,
      showTopGloss: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                CurrencyFormatter.format(draw.amount),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.30), width: 1),
                ),
                child: Text(
                  _statusLabel(draw.status, draw.disbursementStatus),
                  style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...steps.asMap().entries.map((e) => _TimelineRow(
                step: e.value,
                isLast: e.key == steps.length - 1,
              )),
        ],
      ),
    );
  }
}

class _TStep {
  final IconData icon;
  final String label;
  final String? sublabel;
  final bool done;
  final Color color;
  const _TStep({
    required this.icon,
    required this.label,
    this.sublabel,
    required this.done,
    required this.color,
  });
}

class _TimelineRow extends StatelessWidget {
  final _TStep step;
  final bool isLast;
  const _TimelineRow({required this.step, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: step.done
                    ? step.color.withValues(alpha: 0.15)
                    : cs.surfaceContainerHighest,
                border: Border.all(
                  color: step.done
                      ? step.color.withValues(alpha: 0.50)
                      : cs.outlineVariant,
                  width: 1.5,
                ),
              ),
              child: Icon(
                step.done ? step.icon : Icons.radio_button_unchecked,
                size: 14,
                color: step.done ? step.color : cs.outlineVariant,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: step.done
                    ? step.color.withValues(alpha: 0.25)
                    : cs.outlineVariant.withValues(alpha: 0.25),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  step.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: step.done
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: step.done
                            ? cs.onSurface
                            : cs.onSurfaceVariant,
                      ),
                ),
                if (step.sublabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.sublabel!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Recent advances section ────────────────────────────────────────────────────

class _RecentAdvancesSection extends ConsumerWidget {
  final String employeeId;
  const _RecentAdvancesSection({required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draws = ref.watch(employeeDrawsProvider(employeeId));
    return draws.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(height: 14, width: 140, radius: 6),
          const SizedBox(height: 10),
          for (int i = 0; i < 2; i++) ...[
            GlassCard(
              radius: 14,
              showTopGloss: false,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Skeleton(width: 36, height: 36, radius: 18),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Skeleton(height: 12, width: 80, radius: 6),
                      const SizedBox(height: 4),
                      Skeleton(height: 10, width: 120, radius: 6),
                    ])),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        // Skip draw[0] — shown in timeline; show next up to 3
        final rest = list.skip(1).take(3).toList();
        if (rest.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent advances',
                    style: Theme.of(context).textTheme.titleMedium),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          _FullHistoryScreen(employeeId: employeeId),
                    ),
                  ),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...rest.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AdvanceTile(draw: d),
                )),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _AdvanceTile extends StatelessWidget {
  final DrawRequest draw;
  const _AdvanceTile({required this.draw});

  static final _dateFmt = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final isSent = draw.status == DrawStatus.approved &&
        draw.disbursementStatus == DisbursementStatus.completed;
    final (color, icon, statusLabel) = draw.status == DrawStatus.rejected
        ? (glassDanger, Icons.cancel_outlined, 'Rejected')
        : draw.status == DrawStatus.pending
            ? (glassWarning, Icons.hourglass_empty_outlined, 'Pending')
            : isSent
                ? (const Color(0xFFAB7AFF),
                    Icons.mobile_screen_share_outlined, 'Sent')
                : (glassSuccess, Icons.check_circle_outline, 'Approved');

    return GlassCard(
      radius: 14,
      showTopGloss: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CurrencyFormatter.format(draw.amount),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _dateFmt.format(draw.createdAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                statusLabel,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (draw.status == DrawStatus.rejected &&
              draw.reason != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 12,
                    color: glassDanger.withValues(alpha: 0.65)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    draw.reason!,
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
    );
  }
}

// ── Full history screen (pushed route) ────────────────────────────────────────

class _FullHistoryScreen extends ConsumerWidget {
  final String employeeId;
  const _FullHistoryScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draws = ref.watch(employeeDrawsProvider(employeeId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Advance history')),
      body: GlassBackground(
        child: draws.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const _ErrorView(message: 'Could not load advance history.\nPlease try again.'),
          data: (list) {
            if (list.isEmpty) {
              return const Center(
                child: _EmptyNotice(
                  icon: Icons.history_outlined,
                  message: 'No advance requests yet.',
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AdvanceTile(draw: list[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Mini hours summary ─────────────────────────────────────────────────────────

class _MiniHoursSection extends ConsumerWidget {
  final String employeeId;
  const _MiniHoursSection({required this.employeeId});

  static String _fmtHours(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoursWorked = ref.watch(hoursWorkedProvider(employeeId));

    return GlassCard(
      radius: 16,
      showTopGloss: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.schedule_outlined, size: 18, color: glassBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hours this cycle',
                    style: Theme.of(context).textTheme.labelMedium),
                Text(
                  _fmtHours(hoursWorked),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _FullHoursScreen(employeeId: employeeId),
              ),
            ),
            child: const Text('View all'),
          ),
        ],
      ),
    );
  }
}

// ── Full hours screen (pushed route) ──────────────────────────────────────────

class _FullHoursScreen extends ConsumerWidget {
  final String employeeId;
  const _FullHoursScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(employeeSessionsProvider(employeeId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Hours worked')),
      body: GlassBackground(
        child: sessions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const _ErrorView(message: 'Could not load hours.\nPlease try again.'),
          data: (list) {
            if (list.isEmpty) {
              return const Center(
                child: _EmptyNotice(
                  icon: Icons.schedule_outlined,
                  message: 'No punches recorded yet.',
                ),
              );
            }

            final Map<String, List<TimeSession>> grouped = {};
            for (final s in list) {
              final key =
                  '${s.clockIn.year}-${s.clockIn.month.toString().padLeft(2, '0')}';
              grouped.putIfAbsent(key, () => []).add(s);
            }
            final months = grouped.keys.toList()
              ..sort((a, b) => b.compareTo(a));

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              itemCount: months.length,
              itemBuilder: (_, i) => _MonthSection(
                monthKey: months[i],
                sessions: grouped[months[i]]!,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MonthSection extends StatefulWidget {
  final String monthKey;
  final List<TimeSession> sessions;
  const _MonthSection({required this.monthKey, required this.sessions});

  @override
  State<_MonthSection> createState() => _MonthSectionState();
}

class _MonthSectionState extends State<_MonthSection> {
  bool _expanded = false;

  static const _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _monthLabel() {
    final parts = widget.monthKey.split('-');
    return '${_monthNames[int.parse(parts[1])]} ${parts[0]}';
  }

  static String fmtHours(Duration d) {
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String fmtDateTime(DateTime t) {
    final l = t.toLocal();
    return '${l.day.toString().padLeft(2, '0')} ${_monthNames[l.month]} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final completed =
        widget.sessions.where((s) => s.clockOut != null).toList();
    final total = completed.fold<Duration>(
        Duration.zero, (sum, s) => sum + s.hoursWorked);
    final hasOpen = widget.sessions.any((s) => s.clockOut == null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        radius: 20,
        showTopGloss: false,
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _monthLabel(),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                fmtHours(total),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              Text(
                                ' · ${widget.sessions.length} '
                                'punch${widget.sessions.length == 1 ? '' : 'es'}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: cs.onSurfaceVariant),
                              ),
                              if (hasOpen) ...[
                                Text(' · ',
                                    style: TextStyle(
                                        color: cs.outlineVariant)),
                                Text(
                                  'clocked in',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.green),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1),
              ...widget.sessions.map((s) => _PunchTile(session: s)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PunchTile extends StatelessWidget {
  final TimeSession session;
  const _PunchTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: Icon(Icons.access_time_outlined,
          size: 18, color: cs.onSurfaceVariant),
      title: Text(
        _MonthSectionState.fmtDateTime(session.clockIn),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Text(
        session.clockOut != null
            ? _MonthSectionState.fmtHours(session.hoursWorked)
            : 'In progress',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: session.clockOut != null ? cs.onSurface : Colors.green,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

class _SuccessContent extends StatelessWidget {
  final double amount;
  final VoidCallback onDone;
  const _SuccessContent({required this.amount, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: glassSuccess.withValues(alpha: 0.15),
            border: Border.all(
                color: glassSuccess.withValues(alpha: 0.30), width: 1.5),
          ),
          child: const Icon(Icons.check_circle_outline,
              color: glassSuccess, size: 32),
        ),
        const SizedBox(height: 16),
        Text('Request sent!',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          '${CurrencyFormatter.format(amount)} advance requested',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Text(
          'Usually reviewed within a few hours.\nYou\'ll be notified when it\'s approved.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onDone,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyNotice({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
