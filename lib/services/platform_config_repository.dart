import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/platform_config.dart';

/// The website's dropdown lists. firestore.rules make platform_config/website
/// readable by anyone (the static site loads it) and writable only by the
/// platform admin.
class PlatformConfigRepository {
  final DocumentReference<Map<String, dynamic>> _doc;

  PlatformConfigRepository({FirebaseFirestore? firestore})
      : _doc = (firestore ?? FirebaseFirestore.instance).doc('platform_config/website');

  /// The saved industries, or the defaults until the platform admin saves a list.
  Stream<List<String>> watchIndustries() =>
      _doc.snapshots().map((snap) => industriesFromMap(snap.data()));

  Future<void> saveIndustries(List<String> industries) {
    return _doc.set({
      'industries': industries,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser!.uid,
    });
  }
}
