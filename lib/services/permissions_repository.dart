import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_permissions.dart';

class PermissionsRepository {
  final DocumentReference<Map<String, dynamic>> _doc;

  PermissionsRepository({required String companyId, FirebaseFirestore? firestore})
      : _doc = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('settings')
            .doc('permissions');

  Stream<AppPermissions> watch() {
    return _doc.snapshots().map((doc) =>
        doc.exists ? AppPermissions.fromMap(doc.data()!) : AppPermissions.defaults());
  }

  Future<void> update(AppPermissions permissions) {
    return _doc.set(permissions.toMap(), SetOptions(merge: false));
  }
}
