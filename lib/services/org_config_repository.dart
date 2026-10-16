import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/org_config.dart';

class OrgConfigRepository {
  final DocumentReference<Map<String, dynamic>> _doc;

  OrgConfigRepository({required String companyId, FirebaseFirestore? firestore})
      : _doc = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('settings')
            .doc('org');

  Stream<OrgConfig> watch() =>
      _doc.snapshots().map((snap) => OrgConfig.fromMap(snap.data()));

  Future<void> save(OrgConfig config) => _doc.set(config.toMap());
}
