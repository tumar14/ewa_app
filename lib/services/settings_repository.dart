import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/settings.dart';

/// A settings change the server refused, with a message to show.
class SettingsException implements Exception {
  final String message;
  SettingsException(this.message);
  @override
  String toString() => message;
}

/// Single document at settings/app — all Admin Settings rules (spec
/// section 7) live here so they're configurable without an app update.
class SettingsRepository {
  final DocumentReference<Map<String, dynamic>> _doc;

  final FirebaseFunctions _functions;

  SettingsRepository({required String companyId, FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance,
        _doc = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('settings')
            .doc('app');

  Stream<AppSettings> watch() {
    return _doc.snapshots().map(
          (doc) => doc.exists ? AppSettings.fromMap(doc.data()!) : AppSettings(),
        );
  }

  /// Saves [settings] through the updateSettings function: the server checks every value
  /// (and the platform's ceiling on advances), records who changed what in the audit log,
  /// and keeps the values being replaced at settings/previous so "Restore previous
  /// settings" can undo the change, including a reset. Throws [SettingsException] with a
  /// message fit to show when a value is refused.
  Future<void> update(AppSettings settings) async {
    try {
      await _functions.httpsCallable('updateSettings').call(settings.toMap());
    } on FirebaseFunctionsException catch (e) {
      throw SettingsException(e.code == 'invalid-argument' || e.code == 'permission-denied'
          ? (e.message ?? 'These settings were not accepted.')
          : 'Settings could not be saved right now. Please try again.');
    }
  }

  DocumentReference<Map<String, dynamic>> get _previous => _doc.parent.doc('previous');

  /// The settings as they were before the last save, or null if there is none yet.
  Future<AppSettings?> previous() async {
    final snap = await _previous.get();
    return snap.exists && snap.data() != null ? AppSettings.fromMap(snap.data()!) : null;
  }
}
