import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_permissions.dart';
import '../../models/org_config.dart';
import '../../providers/org_config_providers.dart';
import '../../providers/permissions_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

class PermissionsScreen extends ConsumerWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permAsync = ref.watch(appPermissionsProvider);
    final orgConfig =
        ref.watch(orgConfigProvider).valueOrNull ?? OrgConfig.defaults();
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(title: const Text('Role Permissions')),
        body: permAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (perms) =>
              _PermissionsEditor(perms: perms, orgConfig: orgConfig),
        ),
      ),
    );
  }
}

class _PermissionsEditor extends ConsumerStatefulWidget {
  final AppPermissions perms;
  final OrgConfig orgConfig;
  const _PermissionsEditor({required this.perms, required this.orgConfig});

  @override
  ConsumerState<_PermissionsEditor> createState() => _PermissionsEditorState();
}

class _PermissionsEditorState extends ConsumerState<_PermissionsEditor>
    with SingleTickerProviderStateMixin {
  late AppPermissions _perms;
  late TabController _tabCtrl;
  bool _saving = false;

  List<String> get _roles => widget.orgConfig.roles;

  @override
  void initState() {
    super.initState();
    _perms = widget.perms;
    _tabCtrl = TabController(length: _roles.length + 1, vsync: this);
  }

  @override
  void didUpdateWidget(_PermissionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orgConfig.roles.length != widget.orgConfig.roles.length) {
      _tabCtrl.dispose();
      _tabCtrl = TabController(length: _roles.length + 1, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(permissionsRepositoryProvider).update(_perms);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissions saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(String role, String feature, String action, bool granted) {
    setState(() {
      _perms = _perms.withUpdate(role, feature, action, granted);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Role tab bar ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: TabBar(
              controller: _tabCtrl,
              indicator: BoxDecoration(
                color: glassBlue.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(10),
              ),
              dividerColor: Colors.transparent,
              labelColor: glassBlue,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                ..._roles.map((r) => Tab(
                      icon: Icon(_roleIcon(r), size: 18),
                      text: roleLabel(r),
                    )),
                const Tab(
                    icon: Icon(Icons.shield_outlined, size: 18),
                    text: 'Admin'),
              ],
            ),
          ),
        ),

        // ── Tab content ────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              ..._roles.map((role) => _RoleTab(
                    role: role,
                    perms: _perms,
                    onToggle: (feature, action, granted) =>
                        _toggle(role, feature, action, granted),
                  )),
              _AdminTab(),
            ],
          ),
        ),

        // ── Save bar ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GlassPrimaryButton(
            label: 'Save permissions',
            width: double.infinity,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}

IconData _roleIcon(String role) => switch (role) {
      'worker' => Icons.person_outline,
      'supervisor' => Icons.manage_accounts_outlined,
      _ => Icons.badge_outlined,
    };

// ── Configurable role tab ─────────────────────────────────────────────────────

class _RoleTab extends StatelessWidget {
  final String role;
  final AppPermissions perms;
  final void Function(String feature, String action, bool granted) onToggle;

  const _RoleTab({
    required this.role,
    required this.perms,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: featureCatalogue.length,
      itemBuilder: (context, i) {
        final feature = featureCatalogue[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _FeatureCard(
            feature: feature,
            grantedActions: perms.roles[role]?[feature.key] ?? [],
            onToggle: (action, granted) =>
                onToggle(feature.key, action, granted),
          ),
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final FeatureDef feature;
  final List<String> grantedActions;
  final void Function(String action, bool granted) onToggle;

  const _FeatureCard({
    required this.feature,
    required this.grantedActions,
    required this.onToggle,
  });

  static const _actionLabels = {
    'view':    'View',
    'create':  'Create',
    'edit':    'Edit',
    'delete':  'Delete',
    'approve': 'Approve',
  };

  static const _actionColors = {
    'view':    glassBlue,
    'create':  glassSuccess,
    'edit':    glassWarning,
    'delete':  glassDanger,
    'approve': Color(0xFFAB7AFF),
  };

  @override
  Widget build(BuildContext context) {
    final hasAny = grantedActions.isNotEmpty;

    return GlassCard(
      radius: 16,
      showTopGloss: false,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (hasAny ? glassBlue : Colors.white)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _featureIcon(feature.key),
                  size: 18,
                  color: hasAny
                      ? glassBlue
                      : Colors.white.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feature.label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: hasAny
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.50),
                          ),
                    ),
                    Text(
                      feature.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              // "No access" badge when nothing is granted
              if (!hasAny)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: glassDanger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: glassDanger.withValues(alpha: 0.25), width: 1),
                  ),
                  child: Text('No access',
                      style: TextStyle(
                          fontSize: 10,
                          color: glassDanger.withValues(alpha: 0.80),
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.07), height: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: feature.actions.map((action) {
              final granted = grantedActions.contains(action);
              final color = _actionColors[action] ?? glassBlue;
              return GestureDetector(
                onTap: () => onToggle(action, !granted),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: granted
                        ? color.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: granted
                          ? color.withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.10),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        granted
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        size: 14,
                        color: granted
                            ? color
                            : Colors.white.withValues(alpha: 0.25),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _actionLabels[action] ?? action,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: granted
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: granted
                              ? color
                              : Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  IconData _featureIcon(String key) => switch (key) {
        'drawRequests'      => Icons.payments_outlined,
        'approvals'         => Icons.fact_check_outlined,
        'workforce'         => Icons.groups_outlined,
        'payroll'           => Icons.receipt_long_outlined,
        'disbursements'     => Icons.send_to_mobile_outlined,
        'supervisorSignoff' => Icons.rule_outlined,
        'auditLog'          => Icons.history_outlined,
        'reports'           => Icons.bar_chart_outlined,
        'settings'          => Icons.settings_outlined,
        _                   => Icons.lock_outline,
      };
}

// ── Admin tab — read-only ─────────────────────────────────────────────────────

class _AdminTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(20),
          surfaceColor: glassBlue.withValues(alpha: 0.06),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glassBlue.withValues(alpha: 0.12),
                  border: Border.all(
                      color: glassBlue.withValues(alpha: 0.25), width: 1.5),
                ),
                child: const Icon(Icons.shield_outlined,
                    color: glassBlue, size: 28),
              ),
              const SizedBox(height: 14),
              Text('Full Access',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: glassBlue,
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 6),
              Text(
                'Admins always have unrestricted access to every feature.\n'
                'This cannot be changed.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Divider(color: Colors.white.withValues(alpha: 0.08)),
              const SizedBox(height: 16),
              ...featureCatalogue.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            size: 16, color: glassSuccess.withValues(alpha: 0.80)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(f.label,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withValues(alpha: 0.70),
                                    ))),
                        Text(
                          f.actions.join(' · '),
                          style: TextStyle(
                              fontSize: 11,
                              color: glassBlue.withValues(alpha: 0.70),
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
