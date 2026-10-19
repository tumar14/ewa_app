import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enquiry.dart';
import '../../providers/enquiry_providers.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';
import 'create_company_screen.dart';

/// Website submissions waiting for the platform admin: employer registration
/// requests and contact messages. Handling one never grants access by itself;
/// "Create company" opens the normal create-company form, prefilled, and the
/// platform admin still sets the first admin's temporary password.
class EnquiriesScreen extends ConsumerWidget {
  const EnquiriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enquiries = ref.watch(enquiriesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Website enquiries')),
      body: GlassBackground(
        child: enquiries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load enquiries: $e')),
          data: (list) {
            if (list.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No enquiries yet. Employer registration requests and contact '
                    'messages from the website appear here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, i) => _EnquiryCard(enquiry: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _EnquiryCard extends ConsumerWidget {
  final Enquiry enquiry;
  const _EnquiryCard({required this.enquiry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = enquiry;
    final date = e.createdAt.toLocal().toString().split('.').first;
    final details = <String>[
      if (e.contactName.isNotEmpty) e.contactName,
      if (e.jobTitle.isNotEmpty) e.jobTitle,
      if (e.contactEmail.isNotEmpty) e.contactEmail,
      if (e.contactPhone.isNotEmpty) e.contactPhone,
      if (e.employeeCount != null) '${e.employeeCount} employees',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        radius: 16,
        showTopGloss: false,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(e.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                GlassChip(
                  label: e.isEmployerRegistration ? 'Employer' : 'Contact',
                  color: glassBlue,
                ),
                const SizedBox(width: 6),
                GlassChip(
                  label: e.handled ? 'Handled' : 'New',
                  color: e.handled ? glassSuccess : glassWarning,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(date, style: TextStyle(fontSize: 12, color: context.onSurface(0.55))),
            const SizedBox(height: 8),
            SelectableText(details.join(' · '),
                style: TextStyle(color: context.onSurface(0.80))),
            if (e.message.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(e.message),
            ],
            if (e.note != null && e.note!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Note: ${e.note}',
                  style: TextStyle(fontSize: 12, color: context.onSurface(0.65))),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (e.isEmployerRegistration && !e.handled)
                  FilledButton.icon(
                    icon: const Icon(Icons.add_business_outlined, size: 18),
                    label: const Text('Create company'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CreateCompanyScreen(enquiry: e))),
                  ),
                if (e.contactEmail.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy email'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: e.contactEmail));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Email copied.')));
                    },
                  ),
                TextButton(
                  onPressed: () => ref
                      .read(enquiryRepositoryProvider)
                      .setHandled(e.id, !e.handled),
                  child: Text(e.handled ? 'Mark as new' : 'Mark as handled'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
