import '../../brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/settings_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

/// Shown once on first login until the employee acknowledges the policy.
/// Writes `consentedAt` to their Firestore doc to clear the gate.
class ConsentScreen extends ConsumerStatefulWidget {
  final String employeeId;
  const ConsentScreen({super.key, required this.employeeId});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _agreeing = false;

  Future<void> _agree() async {
    setState(() => _agreeing = true);
    try {
      await ref
          .read(employeeRepositoryProvider)
          .acceptConsent(widget.employeeId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save consent: $e')),
        );
        setState(() => _agreeing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final companyName =
        ref.watch(appSettingsProvider).valueOrNull?.companyName ?? '';
    final appName =
        companyName.isNotEmpty ? '$companyName — ${Brand.name}' : Brand.name;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: glassBlue.withOpacity(0.15),
                    border: Border.all(
                        color: glassBlue.withOpacity(0.30), width: 1),
                  ),
                  child: const Icon(Icons.policy_outlined,
                      color: glassBlue, size: 26),
                ),
                const SizedBox(height: 20),
                Text(
                  'Privacy & Terms',
                  style: TextStyle(
                    color: context.onSurface(),
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  appName,
                  style: TextStyle(
                      color: context.onSurface(0.60), fontSize: 13),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: GlassCard(
                    radius: 16,
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: _PolicyText(companyName: companyName),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                GlassPrimaryButton(
                  label: 'I have read and agree',
                  loading: _agreeing,
                  width: double.infinity,
                  onPressed: _agreeing ? null : _agree,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PolicyText extends StatelessWidget {
  final String companyName;
  const _PolicyText({required this.companyName});

  @override
  Widget build(BuildContext context) {
    final name = companyName.isNotEmpty ? companyName : 'Your employer';
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Widget section(String title, String body) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(title,
                style: ts.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(body,
                style: ts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Before using the ${Brand.name} earned wage access service, please '
          'read and agree to the following terms.',
          style: ts.bodyMedium,
        ),
        section(
          'Data collected',
          'We collect your name, email address, work hours (clock-in/out '
          'timestamps), salary information, and mobile money or bank details '
          'you provide for disbursement purposes.',
        ),
        section(
          'How your data is used',
          'Your data is used solely to calculate your earned wages, process '
          'wage advance requests, and record payments to your designated '
          'account. $name will not sell or share your data with third parties '
          'except as required by Eswatini law.',
        ),
        section(
          'Advance terms',
          'An advance is a portion of wages you have already earned. '
          'A service fee applies to each advance (shown before you confirm). '
          'The total amount (advance + fee) is deducted from your next '
          'payslip. You may not advance more than the configured percentage '
          'of your cycle earnings.',
        ),
        section(
          'Data retention',
          'Your data is retained for a minimum of seven years in accordance '
          'with Eswatini labour record-keeping requirements. You may request '
          'a copy of your data by contacting your HR administrator.',
        ),
        section(
          'Your rights',
          'You have the right to access, correct, or request deletion of your '
          'personal data, subject to legal obligations. Contact your HR '
          'administrator to exercise these rights.',
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
