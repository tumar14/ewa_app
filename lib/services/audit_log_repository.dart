import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/audit_log_entry.dart';

/// Read-only access to audit_log — written exclusively by Cloud Functions
/// (see functions/src/index.ts); firestore.rules deny all client writes.
class AuditLogRepository {
  final CollectionReference<Map<String, dynamic>> _collection;

  AuditLogRepository({required String companyId, FirebaseFirestore? firestore})
      : _collection = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('audit_log');

  /// Most recent entries first (spec section 4/10: full audit trail).
  Stream<List<AuditLogEntry>> watchRecent({int limit = 200}) {
    return _collection
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AuditLogEntry.fromMap(d.id, d.data())).toList());
  }
}
