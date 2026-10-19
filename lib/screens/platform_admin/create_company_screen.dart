import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enquiry.dart';
import '../../providers/enquiry_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../services/platform_admin_service.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

/// Platform-admin flow: create a company shell + its first admin employee
/// in one step (a company with zero admins would be a dead end — nobody
/// could sign in to upload a roster or add more employees).
class CreateCompanyScreen extends ConsumerStatefulWidget {
  /// When opened from a website enquiry, the form starts prefilled and the
  /// enquiry is marked handled once the company is created. Nothing is created
  /// or granted until the platform admin submits the form.
  final Enquiry? enquiry;

  const CreateCompanyScreen({super.key, this.enquiry});

  @override
  ConsumerState<CreateCompanyScreen> createState() => _CreateCompanyScreenState();
}

class _CreateCompanyScreenState extends ConsumerState<CreateCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _hrEmailCtrl = TextEditingController();
  final _hrPhoneCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'SZL');
  final _adminNameCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();
  final _adminPasswordCtrl = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.enquiry;
    if (e != null) {
      _nameCtrl.text = e.companyName;
      _hrEmailCtrl.text = e.contactEmail;
      _hrPhoneCtrl.text = e.contactPhone;
      _adminNameCtrl.text = e.contactName;
      _adminEmailCtrl.text = e.contactEmail;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _hrEmailCtrl, _hrPhoneCtrl, _currencyCtrl,
      _adminNameCtrl, _adminEmailCtrl, _adminPasswordCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref.read(platformAdminServiceProvider).createCompany(
            name: _nameCtrl.text.trim(),
            hrEmail: _hrEmailCtrl.text.trim(),
            hrPhone: _hrPhoneCtrl.text.trim(),
            currency: _currencyCtrl.text.trim(),
            adminName: _adminNameCtrl.text.trim(),
            adminEmail: _adminEmailCtrl.text.trim(),
            adminTemporaryPassword: _adminPasswordCtrl.text,
          );
      final enquiry = widget.enquiry;
      if (enquiry != null) {
        try {
          await ref.read(enquiryRepositoryProvider).setHandled(enquiry.id, true,
              note: 'Company created (code ${result.shortCode})');
        } catch (_) {
          // The company exists either way; the enquiry can be marked by hand.
        }
      }
      if (mounted) {
        Navigator.of(context).pop();
        _showCreated(context, _nameCtrl.text.trim(), result.shortCode);
      }
    } on CreateCompanyException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showCreated(BuildContext context, String name, String shortCode) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Company created'),
        content: Text(
          '$name is ready. Its claim code for the searchable picker is:\n\n$shortCode\n\n'
          'Share this with HR — it lets workers find the company directly '
          'instead of searching by name.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Add Company')),
      body: GlassBackground(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Company details',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: context.onSurface(0.80)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Company name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hrEmailCtrl,
                decoration: const InputDecoration(labelText: 'HR email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hrPhoneCtrl,
                decoration: const InputDecoration(labelText: 'HR phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _currencyCtrl,
                decoration: const InputDecoration(labelText: 'Currency code', hintText: 'e.g. SZL'),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 24),
              Text(
                'First admin',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: context.onSurface(0.80)),
              ),
              const SizedBox(height: 4),
              Text(
                'This person can sign in immediately and add more employees.',
                style: TextStyle(fontSize: 12, color: context.onSurface(0.55)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _adminNameCtrl,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _adminEmailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _adminPasswordCtrl,
                decoration: const InputDecoration(labelText: 'Temporary password'),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              GlassPrimaryButton(
                label: _saving ? '' : 'Create company',
                loading: _saving,
                width: double.infinity,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
