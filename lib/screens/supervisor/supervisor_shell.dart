import 'package:flutter/material.dart';
import '../admin/supervisor_signoff_screen.dart';

/// What a supervisor sees: the daily sign-off of hours and nothing else. They get names and
/// times from the server, never employee records, pay rates or payout details.
class SupervisorShell extends StatelessWidget {
  const SupervisorShell({super.key});

  @override
  Widget build(BuildContext context) => const SupervisorSignoffScreen(isHome: true);
}
