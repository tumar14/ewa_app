import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/settlement.dart';

/// Reads settlements straight from Firestore (admins only, see
/// firestore.rules); every change goes through a Cloud Function so the
/// status, outstanding amount and exceptions are always derived server-side.
class SettlementRepository {
  final CollectionReference<Map<String, dynamic>> _collection;
  final FirebaseFunctions _functions;

  SettlementRepository({
    required String companyId,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _collection = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('settlements'),
        _functions = functions ?? FirebaseFunctions.instance;

  Stream<List<Settlement>> watchAll() {
    return _collection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Settlement.fromMap(d.id, d.data())).toList());
  }

  Stream<Settlement?> watchOne(String id) {
    return _collection
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? Settlement.fromMap(d.id, d.data()!) : null);
  }

  Stream<List<SettlementItem>> watchItems(String id) {
    return _collection
        .doc(id)
        .collection('items')
        .snapshots()
        .map((snap) => snap.docs.map((d) => SettlementItem.fromMap(d.data())).toList());
  }

  Stream<List<SettlementException>> watchExceptions(String id) {
    return _collection
        .doc(id)
        .collection('exceptions')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => SettlementException.fromMap(d.id, d.data())).toList());
  }

  Future<void> createForRun(String payrollRunId) =>
      _call('createSettlement', {'payrollRunId': payrollRunId});

  Future<void> confirmDeductions(String settlementId, int confirmedMinor) => _call(
      'confirmDeductions', {'settlementId': settlementId, 'confirmedMinor': confirmedMinor});

  Future<void> resolveException(String settlementId, String exceptionId, String note) => _call(
      'resolveException',
      {'settlementId': settlementId, 'exceptionId': exceptionId, 'note': note});

  Future<void> cancel(String settlementId, String reason) =>
      _call('cancelSettlement', {'settlementId': settlementId, 'reason': reason});

  Future<void> _call(String name, Map<String, dynamic> data) async {
    await _functions.httpsCallable(name).call(data);
  }
}

/// Display-ready message for a failed settlement action.
String settlementErrorMessage(Object error) {
  if (error is FirebaseFunctionsException && error.message != null) {
    return error.message!;
  }
  return 'Something went wrong. Please check your connection and try again.';
}
