import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/firebase_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _submitting = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).sendPasswordResetEmail(email);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      // Always show the success message — don't confirm whether the email exists.
      if (mounted) setState(() => _sent = true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Reset password')),
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: _sent
                  ? _SuccessBanner(email: _emailCtrl.text.trim())
                  : GlassCard(
                      radius: 24,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Forgot your password?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Enter your account email and we\'ll send you a reset link.',
                            style: TextStyle(
                                color: Color(0x99FFFFFF), fontSize: 13),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon:
                                  Icon(Icons.email_outlined),
                            ),
                            keyboardType:
                                TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _send(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(_error!,
                                style: TextStyle(
                                    color: cs.error, fontSize: 13)),
                          ],
                          const SizedBox(height: 20),
                          GlassPrimaryButton(
                            label: 'Send reset link',
                            loading: _submitting,
                            width: double.infinity,
                            onPressed: _submitting ? null : _send,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String email;
  const _SuccessBanner({required this.email});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glassSuccess.withOpacity(0.15),
              border: Border.all(
                  color: glassSuccess.withOpacity(0.30), width: 1),
            ),
            child: const Icon(Icons.mark_email_read_outlined,
                size: 36, color: glassSuccess),
          ),
          const SizedBox(height: 20),
          const Text(
            'Check your inbox',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'If $email has an account, a reset link was sent.\n'
            'Check your spam folder if it doesn\'t arrive within a few minutes.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0x99FFFFFF), fontSize: 13),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }
}
