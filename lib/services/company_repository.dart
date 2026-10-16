import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/company.dart';

/// Public company directory — used by the claim screen's company picker
/// (search list + short-code entry) and for pre-login branding. Reads only;
/// companies are created exclusively via the platform-admin `createCompany`
/// Cloud Function.
class CompanyRepository {
  final CollectionReference<Map<String, dynamic>> _companies;
  final CollectionReference<Map<String, dynamic>> _codes;

  CompanyRepository({FirebaseFirestore? firestore})
      : _companies =
            (firestore ?? FirebaseFirestore.instance).collection('companies'),
        _codes = (firestore ?? FirebaseFirestore.instance)
            .collection('company_codes');

  /// Active companies for the searchable picker, sorted by name.
  Stream<List<Company>> watchActive() {
    return _companies.where('active', isEqualTo: true).snapshots().map(
          (snap) => snap.docs.map((d) => Company.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
        );
  }

  /// Every company including inactive ones — platform-admin company list
  /// only. Still just the public directory doc; never touches a company's
  /// employees/draws/payroll/audit subcollections.
  Stream<List<Company>> watchAll() {
    return _companies.snapshots().map(
          (snap) => snap.docs.map((d) => Company.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
        );
  }

  /// Suspends/reactivates a company. A plain client write (not a Cloud
  /// Function) — firestore.rules already restrict companies/{id} writes to
  /// the platformAdmin custom claim, so this is safe directly from the app.
  Future<void> setActive(String companyId, bool active) {
    return _companies.doc(companyId).update({'active': active});
  }

  Future<Company?> get(String companyId) async {
    final doc = await _companies.doc(companyId).get();
    return doc.exists ? Company.fromMap(doc.id, doc.data()!) : null;
  }

  /// Resolves a short code (case/space-insensitive) to a company, or null
  /// if the code doesn't exist or points at an inactive company.
  Future<Company?> getByShortCode(String code) async {
    final normalized = code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return null;
    final pointer = await _codes.doc(normalized).get();
    final companyId = pointer.data()?['companyId'] as String?;
    if (companyId == null) return null;
    final company = await get(companyId);
    return (company != null && company.active) ? company : null;
  }
}
