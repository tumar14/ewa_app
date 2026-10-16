import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/org_config.dart';
import '../../models/rate_matrix.dart';
import '../../providers/org_config_providers.dart';
import '../../providers/rates_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

class RateMatrixScreen extends ConsumerWidget {
  const RateMatrixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matrixAsync = ref.watch(rateMatrixProvider);
    final orgConfig =
        ref.watch(orgConfigProvider).valueOrNull ?? OrgConfig.defaults();
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(title: const Text('Rate Matrix')),
        body: matrixAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (matrix) =>
              _RateMatrixEditor(matrix: matrix, orgConfig: orgConfig),
        ),
      ),
    );
  }
}

class _RateMatrixEditor extends ConsumerStatefulWidget {
  final RateMatrix matrix;
  final OrgConfig orgConfig;
  const _RateMatrixEditor({required this.matrix, required this.orgConfig});

  @override
  ConsumerState<_RateMatrixEditor> createState() => _RateMatrixEditorState();
}

class _RateMatrixEditorState extends ConsumerState<_RateMatrixEditor> {
  // _ctrls[department][role] = controller
  final Map<String, Map<String, TextEditingController>> _ctrls = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final dept in widget.orgConfig.departments) {
      _ctrls[dept] = {};
      for (final role in widget.orgConfig.roles) {
        final rate = widget.matrix.rateFor(dept, role);
        _ctrls[dept]![role] = TextEditingController(
          text: rate != null ? rate.toStringAsFixed(2) : '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final roleMap in _ctrls.values) {
      for (final ctrl in roleMap.values) { ctrl.dispose(); }
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      var matrix = RateMatrix.empty();
      for (final dept in widget.orgConfig.departments) {
        for (final role in widget.orgConfig.roles) {
          final text = _ctrls[dept]![role]!.text.trim();
          final rate = double.tryParse(text);
          if (rate != null && rate > 0) {
            matrix = matrix.withRate(dept, role, rate);
          }
        }
      }
      await ref.read(ratesRepositoryProvider).save(matrix);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rate matrix saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              // Description card
              GlassCard(
                radius: 14,
                showTopGloss: false,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                surfaceColor: glassBlue.withValues(alpha: 0.05),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: glassBlue.withValues(alpha: 0.70)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Set standard hourly rates (SZL) by department and role. '
                        'These appear as suggestions when adding or editing an employee.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Header row
              if (widget.orgConfig.roles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Row(
                    children: [
                      const Expanded(flex: 3, child: SizedBox()),
                      ...widget.orgConfig.roles.map(
                        (role) => Expanded(
                          flex: 2,
                          child: Text(
                            roleLabel(role),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Department rows
              ...widget.orgConfig.departments.map((dept) {
                final deptCtrls = _ctrls[dept];
                if (deptCtrls == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    radius: 14,
                    showTopGloss: false,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            dept,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        ...widget.orgConfig.roles.asMap().entries.map((e) {
                          final isLast =
                              e.key == widget.orgConfig.roles.length - 1;
                          return Expanded(
                            flex: 2,
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: 6,
                                right: isLast ? 0 : 6,
                              ),
                              child: TextFormField(
                                controller: deptCtrls[e.value],
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  prefixText: 'E ',
                                  prefixStyle: TextStyle(fontSize: 12),
                                  hintText: '—',
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  isDense: true,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GlassPrimaryButton(
            label: 'Save rates',
            width: double.infinity,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}
