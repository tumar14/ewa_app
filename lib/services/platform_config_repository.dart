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

  DocumentReference<Map<String, dynamic>> get _limits => _doc.parent.doc('limits');

  /// The highest share of earned wages any company may allow to be advanced (default 50%).
  Stream<double> watchDrawCeiling() => _limits.snapshots().map((snap) {
        final v = snap.data()?['maxDrawPercentCeiling'];
        return v is num && v >= 0.05 && v <= 1 ? v.toDouble() : 0.5;
      });

  Future<void> saveDrawCeiling(double ceiling) {
    return _limits.set({
      'maxDrawPercentCeiling': ceiling,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser!.uid,
    });
  }

  Future<void> saveIndustries(List<String> industries) {
    return _doc.set({
      'industries': industries,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser!.uid,
    });
  }
}
