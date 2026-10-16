import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/org_config.dart';
import '../../providers/org_config_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

class OrgConfigScreen extends ConsumerWidget {
  const OrgConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(orgConfigProvider);
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(title: const Text('Organisation')),
        body: configAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (config) => _OrgConfigEditor(config: config),
        ),
      ),
    );
  }
}

class _OrgConfigEditor extends ConsumerStatefulWidget {
  final OrgConfig config;
  const _OrgConfigEditor({required this.config});

  @override
  ConsumerState<_OrgConfigEditor> createState() => _OrgConfigEditorState();
}

class _OrgConfigEditorState extends ConsumerState<_OrgConfigEditor> {
  late List<String> _departments;
  late List<String> _roles;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _departments = List.from(widget.config.departments);
    _roles = List.from(widget.config.roles);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(orgConfigRepositoryProvider).save(
            OrgConfig(departments: _departments, roles: _roles),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _showInputDialog(
      String title, String hint, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _addDepartment() async {
    final value =
        await _showInputDialog('Add department', 'e.g. Embroidery', '');
    if (value == null || value.isEmpty) return;
    if (_departments.contains(value)) return;
    setState(() => _departments.add(value));
  }

  void _editDepartment(int index) async {
    final value = await _showInputDialog(
        'Edit department', 'Department name', _departments[index]);
    if (value == null || value.isEmpty) return;
    if (value == _departments[index]) return;
    if (_departments.contains(value)) return;
    setState(() => _departments[index] = value);
  }

  void _addRole() async {
    final value = await _showInputDialog(
        'Add role', 'e.g. line_leader or Line Leader', '');
    if (value == null || value.isEmpty) return;
    if (_roles.contains(value) || value.toLowerCase() == 'admin') return;
    setState(() => _roles.add(value));
  }

  void _editRole(int index) async {
    final value = await _showInputDialog(
        'Edit role', 'Role name', _roles[index]);
    if (value == null || value.isEmpty) return;
    if (value == _roles[index]) return;
    if (_roles.contains(value) || value.toLowerCase() == 'admin') return;
    setState(() => _roles[index] = value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              // ── Departments ─────────────────────────────────────────────
              _SectionHeader(
                label: 'Departments',
                addLabel: 'Add department',
                onAdd: _addDepartment,
              ),
              const SizedBox(height: 8),
              GlassCard(
                radius: 14,
                showTopGloss: false,
                padding: EdgeInsets.zero,
                child: _departments.isEmpty
                    ? _EmptyHint(hint: 'No departments — tap Add to create one')
                    : ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: _departments.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final item = _departments.removeAt(oldIndex);
                            _departments.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, i) => _ConfigRow(
                          key: ValueKey(_departments[i]),
                          index: i,
                          label: _departments[i],
                          onEdit: () => _editDepartment(i),
                          onDelete: () =>
                              setState(() => _departments.removeAt(i)),
                        ),
                      ),
              ),
              const SizedBox(height: 20),

              // ── Roles ────────────────────────────────────────────────────
              _SectionHeader(
                label: 'Roles',
                addLabel: 'Add role',
                onAdd: _addRole,
              ),
              const SizedBox(height: 8),
              GlassCard(
                radius: 14,
                showTopGloss: false,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (_roles.isEmpty)
                      _EmptyHint(hint: 'No roles — tap Add to create one')
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: _roles.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            final item = _roles.removeAt(oldIndex);
                            _roles.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, i) => _ConfigRow(
                          key: ValueKey(_roles[i]),
                          index: i,
                          label: roleLabel(_roles[i]),
                          sublabel:
                              roleLabel(_roles[i]) != _roles[i] ? _roles[i] : null,
                          onEdit: () => _editRole(i),
                          onDelete: () =>
                              setState(() => _roles.removeAt(i)),
                        ),
                      ),
                    // Admin — always locked, always present
                    if (_roles.isNotEmpty)
                      Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.06)),
                    ListTile(
                      leading: const Icon(Icons.shield_outlined,
                          color: Color(0xFFAB7AFF), size: 20),
                      title: const Text('Admin'),
                      subtitle: Text(
                        'System role — always present',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12),
                      ),
                      trailing: const Icon(Icons.lock_outline,
                          size: 18, color: Colors.white24),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GlassPrimaryButton(
            label: 'Save configuration',
            width: double.infinity,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final String addLabel;
  final VoidCallback onAdd;

  const _SectionHeader({
    required this.label,
    required this.addLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.40),
                letterSpacing: 1.0,
              ),
        ),
        const Spacer(),
        TextButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: Text(addLabel, style: const TextStyle(fontSize: 13)),
          style: TextButton.styleFrom(
              foregroundColor: glassBlue,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
          onPressed: onAdd,
        ),
      ],
    );
  }
}

class _ConfigRow extends StatelessWidget {
  final int index;
  final String label;
  final String? sublabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ConfigRow({
    required super.key,
    required this.index,
    required this.label,
    this.sublabel,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: key,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: ReorderableDragStartListener(
        index: index,
        child: Icon(Icons.drag_handle,
            size: 22, color: Colors.white.withValues(alpha: 0.25)),
      ),
      title: Text(label),
      subtitle: sublabel != null
          ? Text(sublabel!,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.30)))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined,
                size: 20, color: Colors.white.withValues(alpha: 0.45)),
            onPressed: onEdit,
            tooltip: 'Edit',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 20, color: glassDanger),
            onPressed: onDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String hint;
  const _EmptyHint({required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        hint,
        style: TextStyle(
            fontSize: 13, color: Colors.white.withValues(alpha: 0.35)),
      ),
    );
  }
}
