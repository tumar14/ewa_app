import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/company.dart';
import '../../providers/company_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../services/claim_service.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

/// Employee-first onboarding, now across many companies: a worker first
/// picks (or is deep-linked to) their employer, then claims their seat from
/// that company's roster exactly as before — employee number + full name +
/// the HR-issued one-time claim code. On success we sign them straight in
/// and the AuthGate routes them through the normal consent flow.
class ClaimAccountScreen extends ConsumerStatefulWidget {
  const ClaimAccountScreen({super.key});

  @override
  ConsumerState<ClaimAccountScreen> createState() => _ClaimAccountScreenState();
}

class _ClaimAccountScreenState extends ConsumerState<ClaimAccountScreen> {
  Company? _selectedCompany;

  @override
  void initState() {
    super.initState();
    // Best-effort deep link: https://<host>/claim?company=<shortCode> (web
    // only — mobile deep linking is a future enhancement, out of scope here).
    if (kIsWeb) {
      final code = Uri.base.queryParameters['company'];
      if (code != null && code.trim().isNotEmpty) {
        Future(() => _resolveByCode(code, silent: true));
      }
    }
  }

  Future<void> _resolveByCode(String code, {bool silent = false}) async {
    final company = await ref.read(companyRepositoryProvider).getByShortCode(code);
    if (!mounted) return;
    if (company != null) {
      setState(() => _selectedCompany = company);
    } else if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No company found with that code.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(_selectedCompany == null ? 'Claim your account' : _selectedCompany!.name),
        leading: _selectedCompany == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selectedCompany = null),
              ),
      ),
      body: GlassBackground(
        child: SafeArea(
          child: _selectedCompany == null
              ? _CompanyPickerStep(
                  onSelected: (c) => setState(() => _selectedCompany = c),
                  onCode: (code) => _resolveByCode(code),
                )
              : _ClaimFormStep(company: _selectedCompany!),
        ),
      ),
    );
  }
}

/// Step 1: find the employer. Primary path is a live search over the public
/// company directory; secondary path is a short code HR can hand out
/// directly (also what a `?company=` deep link resolves via).
class _CompanyPickerStep extends ConsumerStatefulWidget {
  final ValueChanged<Company> onSelected;
  final ValueChanged<String> onCode;
  const _CompanyPickerStep({required this.onSelected, required this.onCode});

  @override
  ConsumerState<_CompanyPickerStep> createState() => _CompanyPickerStepState();
}

class _CompanyPickerStepState extends ConsumerState<_CompanyPickerStep> {
  final _searchCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _useCode = false;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final companiesAsync = ref.watch(activeCompaniesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Which company do you work for?',
                style: TextStyle(color: context.onSurface(0.60), fontSize: 13),
              ),
              const SizedBox(height: 20),
              GlassCard(
                radius: 24,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_useCode) ...[
                      TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Search companies',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 12),
                      companiesAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => Text('Could not load companies: $e'),
                        data: (companies) {
                          final matches = _query.isEmpty
                              ? companies
                              : companies
                                  .where((c) => c.name.toLowerCase().contains(_query))
                                  .toList();
                          if (matches.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No matching companies.',
                                style: TextStyle(color: context.onSurface(0.55)),
                              ),
                            );
                          }
                          return Column(
                            children: matches
                                .map((c) => _CompanyResultTile(
                                      company: c,
                                      onTap: () => widget.onSelected(c),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ] else ...[
                      TextField(
                        controller: _codeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Company code',
                          hintText: 'Given to you by HR',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: widget.onCode,
                      ),
                      const SizedBox(height: 16),
                      GlassPrimaryButton(
                        label: 'Find company',
                        width: double.infinity,
                        onPressed: () => widget.onCode(_codeCtrl.text),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () => setState(() => _useCode = !_useCode),
                        child: Text(_useCode
                            ? 'Search by name instead'
                            : 'Have a company code instead?'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyResultTile extends StatelessWidget {
  final Company company;
  final VoidCallback onTap;
  const _CompanyResultTile({required this.company, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: glassBlue.withValues(alpha: 0.15),
        child: Text(
          company.name.isNotEmpty ? company.name[0].toUpperCase() : '?',
          style: const TextStyle(color: glassBlue, fontWeight: FontWeight.w600),
        ),
      ),
      title: Text(company.name),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

/// Step 2: the existing claim form, unchanged except it now submits with
/// the chosen company's id.
class _ClaimFormStep extends ConsumerStatefulWidget {
  final Company company;
  const _ClaimFormStep({required this.company});

  @override
  ConsumerState<_ClaimFormStep> createState() => _ClaimFormStepState();
}

class _ClaimFormStepState extends ConsumerState<_ClaimFormStep> {
  final _formKey = GlobalKey<FormState>();
  final _empNumCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _claimCodeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _empNumCtrl, _nameCtrl, _claimCodeCtrl, _emailCtrl, _passwordCtrl,
      _confirmCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(claimServiceProvider).claim(
            companyId: widget.company.id,
            employeeNumber: _empNumCtrl.text.trim(),
            fullName: _nameCtrl.text.trim(),
            claimCode: _claimCodeCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      // Claim succeeded — sign in so the AuthGate can take over (consent, etc.).
      await ref.read(authServiceProvider).signIn(
            _emailCtrl.text.trim(),
            _passwordCtrl.text,
          );
      if (mounted) Navigator.of(context).pop();
    } on ClaimException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error =
          'Your account was created but we couldn\'t sign you in. Please go '
          'back and sign in with your email and password.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Enter your details exactly as ${widget.company.name} has '
                  'them on file, along with the claim code HR gave you, then '
                  'choose an email and password to sign in with from now on.',
                  style: TextStyle(color: context.onSurface(0.60), fontSize: 13),
                ),
                const SizedBox(height: 20),
                GlassCard(
                  radius: 24,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _empNumCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Employee number',
                          hintText: 'e.g. EMP-001',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _claimCodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Claim code',
                          hintText: 'Given to you by HR',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const Divider(height: 32),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (!v.contains('@')) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordCtrl,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        obscureText: _obscure,
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Minimum 6 characters'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_outlined),
                        ),
                        obscureText: _obscure,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => (v != _passwordCtrl.text)
                            ? 'Passwords do not match'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, size: 16, color: cs.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_error!,
                                  style: TextStyle(color: cs.error, fontSize: 13)),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      GlassPrimaryButton(
                        label: _submitting ? '' : 'Claim account',
                        loading: _submitting,
                        width: double.infinity,
                        onPressed: _submitting ? null : _submit,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Not on file yet? Your employer needs to add you before '
                  'you can claim an account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.onSurface(0.45), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
