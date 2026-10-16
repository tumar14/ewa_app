import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/firebase_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

/// Intercepts the first post-login flow for new employees who were created
/// with a temporary password. Clears `mustChangePassword` after success.
class ForceChangePasswordScreen extends ConsumerStatefulWidget {
  final String employeeId;
  const ForceChangePasswordScreen({super.key, required this.employeeId});

  @override
  ConsumerState<ForceChangePasswordScreen> createState() =>
      _ForceChangePasswordScreenState();
}

class _ForceChangePasswordScreenState
    extends ConsumerState<ForceChangePasswordScreen> {
  final _newPwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _newPwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pw = _newPwCtrl.text;
    final confirm = _confirmCtrl.text;

    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(authServiceProvider).changePassword(pw);
      await ref
          .read(employeeRepositoryProvider)
          .clearMustChangePassword(widget.employeeId);
      // AuthGate will rebuild automatically when mustChangePassword flips to false.
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not update password: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: GlassCard(
                  radius: 24,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: glassWarning.withOpacity(0.15),
                          border: Border.all(
                              color: glassWarning.withOpacity(0.30),
                              width: 1),
                        ),
                        child: const Icon(Icons.lock_reset_outlined,
                            color: glassWarning, size: 24),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Set your password',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A temporary password was used to create your account. '
                        'Please set a personal password before continuing.',
                        style: TextStyle(
                            color: Color(0x99FFFFFF), fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _newPwCtrl,
                        decoration: InputDecoration(
                          labelText: 'New password',
                          prefixIcon:
                              const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureNew
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(
                                () => _obscureNew = !_obscureNew),
                          ),
                          helperText: 'At least 8 characters',
                          helperStyle: const TextStyle(
                              color: Color(0x80FFFFFF)),
                        ),
                        obscureText: _obscureNew,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _confirmCtrl,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon:
                              const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(
                                () =>
                                    _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.error_outline,
                                size: 16, color: cs.error),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: cs.error, fontSize: 13)),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      GlassPrimaryButton(
                        label: 'Set password & continue',
                        loading: _saving,
                        width: double.infinity,
                        onPressed: _saving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
