import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company.dart';
import 'auth_providers.dart';
import 'settings_providers.dart';
import '../services/company_repository.dart';

final companyRepositoryProvider = Provider((ref) => CompanyRepository());

/// The full public company directory — backs the claim screen's searchable
/// picker.
final activeCompaniesProvider = StreamProvider<List<Company>>((ref) {
  return ref.watch(companyRepositoryProvider).watchActive();
});

/// Every company including inactive ones — platform-admin company list.
final allCompaniesProvider = StreamProvider<List<Company>>((ref) {
  return ref.watch(companyRepositoryProvider).watchAll();
});

/// A single company's public info, e.g. for branding or an HR-contact
/// fallback once we know a signed-in user's companyId.
final companyByIdProvider =
    FutureProvider.family<Company?, String>((ref, companyId) {
  return ref.watch(companyRepositoryProvider).get(companyId);
});

/// The signed-in person's company name, for display. Prefers the company's own
/// directory record and falls back to the name in its app settings; empty until
/// either has loaded.
final myCompanyNameProvider = Provider<String>((ref) {
  final companyId = ref.watch(myCompanyIdProvider);
  final fromCompany = companyId == null
      ? null
      : ref.watch(companyByIdProvider(companyId)).valueOrNull?.name;
  if (fromCompany != null && fromCompany.trim().isNotEmpty) return fromCompany.trim();
  return ref.watch(appSettingsProvider).valueOrNull?.companyName.trim() ?? '';
});
