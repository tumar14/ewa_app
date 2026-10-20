import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/firebase_providers.dart';
import '../../widgets/glass_components.dart';
import '../../providers/enquiry_providers.dart';
import 'company_list_screen.dart';
import 'enquiries_screen.dart';
import 'platform_overview_screen.dart';
import 'platform_settings_screen.dart';
import 'record_payment_screen.dart';

/// Root shell for the platform super-admin. Deliberately minimal and
/// deliberately does NOT surface any company's employees, draws, time
/// sessions, payroll, or audit log anywhere in this tree — the platform
/// admin's authority is limited to creating/managing company shells.
class PlatformAdminShell extends ConsumerWidget {
  const PlatformAdminShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: const Text('Platform Admin'),
        actions: [
          Builder(builder: (context) {
            final count = ref.watch(newEnquiryCountProvider);
            return IconButton(
              tooltip: 'Website enquiries',
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: const Icon(Icons.mark_email_unread_outlined),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EnquiriesScreen()),
              ),
            );
          }),
          IconButton(
            tooltip: 'Overview',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlatformOverviewScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Platform settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlatformSettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Record payment',
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RecordPaymentScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: const GlassBackground(child: CompanyListScreen()),
    );
  }
}
