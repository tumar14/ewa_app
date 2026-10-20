import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/employee.dart';
import '../../models/org_config.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/org_config_providers.dart';
import '../../providers/rates_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

/// Add a new employee (create == true) or edit an existing one.
/// Create mode calls the Cloud Function (creates Auth user + Firestore doc).
/// Edit mode writes directly to Firestore — no email/password change.
class EmployeeFormScreen extends ConsumerStatefulWidget {
  final Employee? employee; // null → create mode

  const EmployeeFormScreen({super.key, this.employee});

  @override
  ConsumerState<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _empNumCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _departmentCtrl;
  late final TextEditingController _acctCtrl;
  late final TextEditingController _bankCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _providerCtrl;

  late String _role;
  late DisbursementMethod _disbursementMethod;
  DateTime? _lastWorkingDay;

  bool _saving = false;
  String? _error;

  bool get _isCreate => widget.employee == null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _empNumCtrl = TextEditingController(text: e?.employeeNumber ?? '');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _passwordCtrl = TextEditingController();
    _rateCtrl = TextEditingController(text: e?.hourlyRate.toStringAsFixed(2) ?? '');
    _pinCtrl = TextEditingController();
    _departmentCtrl = TextEditingController(text: e?.department ?? '');
    _role = e?.role ?? 'worker';
    _disbursementMethod = e?.disbursementMethod ?? DisbursementMethod.bankTransfer;
    _lastWorkingDay = e?.lastWorkingDay;
    _departmentCtrl.addListener(() => setState(() {}));
    _acctCtrl = TextEditingController(text: e?.disbursementDetails['accountNumber'] ?? '');
    _bankCtrl = TextEditingController(text: e?.disbursementDetails['bankName'] ?? '');
    _phoneCtrl = TextEditingController(text: e?.disbursementDetails['phoneNumber'] ?? '');
    _providerCtrl = TextEditingController(text: e?.disbursementDetails['provider'] ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _empNumCtrl, _emailCtrl, _passwordCtrl, _rateCtrl, _pinCtrl,
      _departmentCtrl, _acctCtrl, _bankCtrl, _phoneCtrl, _providerCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _disbursementDetails => switch (_disbursementMethod) {
        DisbursementMethod.bankTransfer => {
            'accountNumber': _acctCtrl.text.trim(),
            'bankName': _bankCtrl.text.trim(),
          },
        DisbursementMethod.mobileMoney => {
            'phoneNumber': _phoneCtrl.text.trim(),
            'provider': _providerCtrl.text.trim(),
          },
        DisbursementMethod.cash => {},
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(employeeRepositoryProvider);
      if (_isCreate) {
        await repo.create(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          temporaryPassword: _passwordCtrl.text,
          hourlyRate: double.parse(_rateCtrl.text.trim()),
          employeeNumber: _empNumCtrl.text.trim(),
          role: _role,
          department: _departmentCtrl.text.trim(),
          pin: _pinCtrl.text.trim().isEmpty ? null : _pinCtrl.text.trim(),
          disbursementMethod: _disbursementMethod,
          disbursementDetails: _disbursementDetails,
        );
      } else {
        final rawPin = _pinCtrl.text.trim();
        await repo.update(
          Employee(
            id: widget.employee!.id,
            name: _nameCtrl.text.trim(),
            department: _departmentCtrl.text.trim(),
            employeeNumber: _empNumCtrl.text.trim(),
            hourlyRate: double.parse(_rateCtrl.text.trim()),
            role: _role,
            qrCode: widget.employee!.qrCode,
            disbursementMethod: _disbursementMethod,
            disbursementDetails: _disbursementDetails,
            fcmToken: widget.employee!.fcmToken,
            active: widget.employee!.active,
            lastWorkingDay: _lastWorkingDay,
          ),
          // null = leave existing PIN; empty = clear it; 4 digits = update it
          rawPin: rawPin.isEmpty ? null : rawPin,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Could not save: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deactivate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate employee?'),
        content: Text(
          '${widget.employee!.name} will no longer be able to sign in. '
          'All their history is preserved.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(employeeRepositoryProvider).deactivate(widget.employee!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Deactivation failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = widget.employee!.email;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send password reset?'),
        content: Text('A reset link will be emailed to $email.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).sendPasswordResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset email sent to $email')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Failed to send reset email: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _rateSuggestion(double rate) {
    final formatted = rate.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: GestureDetector(
        onTap: () => setState(() => _rateCtrl.text = formatted),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: glassBlue.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: glassBlue.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_fix_high, size: 16, color: glassBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Standard rate: E $formatted',
                  style: const TextStyle(fontSize: 13, color: glassBlue),
                ),
              ),
              const Text(
                'Apply',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: glassBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgConfig = ref.watch(orgConfigProvider).valueOrNull ?? OrgConfig.defaults();
    final rateMatrix = ref.watch(rateMatrixProvider).valueOrNull;
    final dept = _departmentCtrl.text.trim();
    final standardRate = (dept.isNotEmpty && rateMatrix != null)
        ? rateMatrix.rateFor(dept, _role)
        : null;
    final showSuggestion = standardRate != null &&
        _rateCtrl.text.trim() != standardRate.toStringAsFixed(2);

    // Non-admin configured roles + always include current role + admin
    final configuredRoles = orgConfig.roles;
    final roleItems = [
      ...configuredRoles,
      if (!configuredRoles.contains(_role) && _role != 'admin') _role,
      'admin',
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(_isCreate ? 'Add Employee' : 'Edit Employee'),
      ),
      body: GlassBackground(
        child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _empNumCtrl,
              decoration: const InputDecoration(
                labelText: 'Employee number',
                hintText: 'e.g. EMP-001',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            if (_isCreate) ...[
              TextFormField(
                controller: _emailCtrl,
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
                controller: _passwordCtrl,
                decoration: const InputDecoration(labelText: 'Temporary password'),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
              ),
              const SizedBox(height: 12),
            ] else if (_emailCtrl.text.isNotEmpty) ...[
              TextFormField(
                controller: _emailCtrl,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.email_outlined),
                  helperText: 'Email cannot be changed here',
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _rateCtrl,
              decoration: const InputDecoration(labelText: 'Hourly rate (SZL)', prefixText: 'E '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
                return null;
              },
            ),
            if (showSuggestion) _rateSuggestion(standardRate),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              dropdownColor: Theme.of(context).colorScheme.surface,
              items: roleItems
                  .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(roleLabel(r)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _role = v!),
            ),
            const SizedBox(height: 12),
            DropdownMenu<String>(
              controller: _departmentCtrl,
              enableFilter: true,
              requestFocusOnTap: true,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Department'),
              helperText: 'Select or type a custom department',
              dropdownMenuEntries: orgConfig.departments
                  .map((d) => DropdownMenuEntry(value: d, label: d))
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pinCtrl,
              decoration: InputDecoration(
                labelText: 'Kiosk PIN (optional)',
                helperText: _isCreate
                    ? '4 digits for kiosk clock-in'
                    : 'Leave blank to keep existing PIN',
              ),
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                if (v.length != 4 || int.tryParse(v) == null) return 'Must be exactly 4 digits';
                return null;
              },
            ),
            if (!_isCreate) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Last working day'),
                subtitle: Text(
                  _lastWorkingDay == null
                      ? 'Not leaving. Set a date when someone resigns or is dismissed, so advances pause before final pay.'
                      : '${_lastWorkingDay!.year}-${_lastWorkingDay!.month.toString().padLeft(2, '0')}-${_lastWorkingDay!.day.toString().padLeft(2, '0')}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_lastWorkingDay != null)
                      IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _lastWorkingDay = null),
                      ),
                    const Icon(Icons.event_outlined),
                  ],
                ),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _lastWorkingDay ?? now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 2),
                  );
                  if (picked != null) setState(() => _lastWorkingDay = picked);
                },
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<DisbursementMethod>(
              initialValue: _disbursementMethod,
              decoration: const InputDecoration(labelText: 'Disbursement method'),
              items: const [
                DropdownMenuItem(
                    value: DisbursementMethod.bankTransfer, child: Text('Bank transfer')),
                DropdownMenuItem(
                    value: DisbursementMethod.mobileMoney, child: Text('Mobile money')),
                DropdownMenuItem(value: DisbursementMethod.cash, child: Text('Cash')),
              ],
              onChanged: (v) => setState(() => _disbursementMethod = v!),
            ),
            const SizedBox(height: 12),
            ..._disbursementFields(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isCreate ? 'Create employee' : 'Save changes'),
            ),
            if (!_isCreate && widget.employee!.active) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                onPressed: _saving ? null : _deactivate,
                child: const Text('Deactivate employee'),
              ),
            ],
            if (!_isCreate && widget.employee!.email.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.lock_reset),
                label: const Text('Send password reset email'),
                onPressed: _saving ? null : _sendPasswordReset,
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  List<Widget> _disbursementFields() => switch (_disbursementMethod) {
        DisbursementMethod.bankTransfer => [
            TextFormField(
              controller: _acctCtrl,
              decoration: const InputDecoration(labelText: 'Account number'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bankCtrl,
              decoration: const InputDecoration(labelText: 'Bank name'),
            ),
          ],
        DisbursementMethod.mobileMoney => [
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            DropdownMenu<String>(
              controller: _providerCtrl,
              enableFilter: true,
              requestFocusOnTap: true,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Provider'),
              helperText: 'Select or type a custom provider name',
              dropdownMenuEntries: const [
                DropdownMenuEntry(value: 'MTN Mobile Money', label: 'MTN Mobile Money'),
                DropdownMenuEntry(value: 'E-Mali', label: 'E-Mali'),
                DropdownMenuEntry(value: 'FNB', label: 'FNB'),
                DropdownMenuEntry(value: 'Standard Bank', label: 'Standard Bank'),
                DropdownMenuEntry(value: 'Nedbank', label: 'Nedbank'),
                DropdownMenuEntry(value: 'Swazi Bank', label: 'Swazi Bank'),
                DropdownMenuEntry(value: 'Eswatini Bank', label: 'Eswatini Bank'),
              ],
            ),
          ],
        DisbursementMethod.cash => [],
      };
}
