import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/settings.dart';

/// Single document at settings/app — all Admin Settings rules (spec
/// section 7) live here so they're configurable without an app update.
class SettingsRepository {
  final DocumentReference<Map<String, dynamic>> _doc;

  SettingsRepository({required String companyId, FirebaseFirestore? firestore})
      : _doc = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('settings')
            .doc('app');

  Stream<AppSettings> watch() {
    return _doc.snapshots().map(
          (doc) => doc.exists ? AppSettings.fromMap(doc.data()!) : AppSettings(),
        );
  }

  Future<void> update(AppSettings settings) {
    return _doc.set(settings.toMap(), SetOptions(merge: true));
  }
}
