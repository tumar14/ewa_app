import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/platform_config.dart';
import '../../providers/platform_config_providers.dart';
import '../../widgets/glass_components.dart';

/// Platform-wide settings only the super admin can change. Today: the industries
/// offered in the Industry dropdown on the website's registration form.
class PlatformSettingsScreen extends ConsumerWidget {
  const PlatformSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(websiteIndustriesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Platform settings')),
      body: GlassBackground(
        child: saved.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load settings: $e')),
          data: (industries) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              IndustriesEditor(
                saved: industries,
                onSave: (list) => ref.read(platformConfigRepositoryProvider).saveIndustries(list),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edits the list of industries: add, remove, reorder, save. The website shows
/// them in this order, and the server only accepts one of them.
class IndustriesEditor extends StatefulWidget {
  final List<String> saved;
  final Future<void> Function(List<String> industries) onSave;
  const IndustriesEditor({super.key, required this.saved, required this.onSave});

  @override
  State<IndustriesEditor> createState() => _IndustriesEditorState();
}

class _IndustriesEditorState extends State<IndustriesEditor> {
  late List<String> _items = List.of(widget.saved);
  final _input = TextEditingController();
  String? _problem;
  bool _saving = false;

  bool get _dirty {
    if (_items.length != widget.saved.length) return true;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i] != widget.saved[i]) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final problem = industryProblem(_input.text, _items);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    setState(() {
      _items.add(cleanIndustryName(_input.text));
      _input.clear();
      _problem = null;
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      setState(() => _problem = 'Keep at least one industry in the list.');
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSave(List.of(_items));
      messenger.showSnackBar(const SnackBar(content: Text('Industries saved. The website now offers them.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Industries on the registration form', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'These fill the Industry dropdown on the website\'s "Register your company" page, in this order. '
            'Drag to reorder. "$kIndustryOther" is always accepted, even if it is not listed.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: (from, to) => setState(() => _items.insert(to, _items.removeAt(from))),
            children: [
              for (final name in _items)
                ListTile(
                  key: ValueKey(name),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(name),
                  trailing: IconButton(
                    tooltip: 'Remove $name',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _items.remove(name)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: kMaxIndustryLength,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Add an industry',
                    errorText: _problem,
                    counterText: '',
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton(onPressed: _add, child: const Text('Add')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _dirty && !_saving ? _save : null,
                child: Text(_saving ? 'Saving…' : 'Save industries'),
              ),
              OutlinedButton(
                onPressed: _saving ? null : () => setState(() => _items = List.of(kDefaultIndustries)),
                child: const Text('Use the standard list'),
              ),
              if (_dirty)
                TextButton(
                  onPressed: _saving ? null : () => setState(() => _items = List.of(widget.saved)),
                  child: const Text('Discard changes'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
