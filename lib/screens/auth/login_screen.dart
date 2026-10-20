import '../../widgets/brand_mark.dart';
import '../../brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/settings_providers.dart';
import '../../theme/glass_theme.dart';
import '../../utils/auth_errors.dart';
import '../../widgets/glass_components.dart';
import 'claim_account_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _submitting = false;
  bool _obscure = true;

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await ref.read(authServiceProvider).signIn(
            _emailController.text.trim(),
            _passwordController.text,
          );
    } catch (e) {
      setState(() => _error = signInErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final companyName =
        ref.watch(appSettingsProvider).valueOrNull?.companyName ?? '';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 24),
                    const BrandMark(size: 76),
                    const SizedBox(height: 20),
                    Text(
                      Brand.name,
                      style: TextStyle(
                        color: context.onSurface(),
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      companyName.isNotEmpty
                          ? '$companyName · ${Brand.tagline}'
                          : Brand.tagline,
                      style: TextStyle(
                        color: context.onSurface(0.55),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    GlassCard(
                      radius: 24,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sign in to your account',
                            style: TextStyle(
                              color: context.onSurface(0.60),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon:
                                  Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon:
                                  const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(
                                    () => _obscure = !_obscure),
                              ),
                            ),
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            autofillHints: const [AutofillHints.password],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.error_outline,
                                    size: 16, color: cs.error),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                        color: cs.error, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ForgotPasswordScreen(),
                                ),
                              ),
                              child: const Text('Forgot password?'),
                            ),
                          ),
                          const SizedBox(height: 4),
                          GlassPrimaryButton(
                            label: _submitting ? '' : 'Sign in',
                            loading: _submitting,
                            width: double.infinity,
                            onPressed: _submitting ? null : _submit,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'First time here?',
                          style: TextStyle(
                              color: context.onSurface(0.55), fontSize: 13),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ClaimAccountScreen(),
                            ),
                          ),
                          child: const Text('Claim your account'),
                        ),
                      ],
                    ),
                    if (companyName.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        companyName,
                        style: TextStyle(
                            color: context.onSurface(0.25), fontSize: 12),
                      ),
                    ],
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
