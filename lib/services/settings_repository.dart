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

  /// Saves [settings]. The values being replaced are kept at settings/previous
  /// first, so "Restore previous settings" can undo the change, including a reset.
  Future<void> update(AppSettings settings) async {
    final current = await _doc.get();
    final batch = _doc.firestore.batch();
    if (current.exists && current.data() != null) {
      batch.set(_previous, {...current.data()!, 'savedAt': FieldValue.serverTimestamp()});
    }
    batch.set(_doc, settings.toMap(), SetOptions(merge: true));
    await batch.commit();
  }

  DocumentReference<Map<String, dynamic>> get _previous => _doc.parent.doc('previous');

  /// The settings as they were before the last save, or null if there is none yet.
  Future<AppSettings?> previous() async {
    final snap = await _previous.get();
    return snap.exists && snap.data() != null ? AppSettings.fromMap(snap.data()!) : null;
  }
}
