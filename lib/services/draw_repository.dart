import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/draw_request.dart';

/// Reads are Firestore streams. Every write goes through a Cloud Function
/// (requestDraw, decideDrawRequest, disburseDraw): firestore.rules deny client
/// writes to draw_requests so the limits are enforced server-side.
class DrawRepository {
  final CollectionReference<Map<String, dynamic>> _collection;
  final FirebaseFunctions _functions;

  DrawRepository({
    required String companyId,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _collection = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('draw_requests'),
        _functions = functions ?? FirebaseFunctions.instance;

  Stream<List<DrawRequest>> watchForEmployee(String employeeId) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => DrawRequest.fromMap(d.id, d.data())).toList());
  }

  Stream<List<DrawRequest>> watchOutstandingForEmployee(String employeeId) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .where('payrollRunId', isNull: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => DrawRequest.fromMap(d.id, d.data())).toList());
  }

  Stream<List<DrawRequest>> watchPending() {
    return _collection
        .where('status', isEqualTo: DrawStatus.pending.name)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => DrawRequest.fromMap(d.id, d.data())).toList());
  }

  /// Asks the server to create a pending request for [amountMinor] cents. Fee
  /// and limits are computed server-side; throws [FirebaseFunctionsException]
  /// with a user-readable message when a limit is exceeded.
  ///
  /// Returns the new request's status: 'approved' when the company approves
  /// automatically, otherwise 'pending'.
  Future<String> requestDraw(int amountMinor) async {
    final result =
        await _functions.httpsCallable('requestDraw').call({'amountMinor': amountMinor});
    final data = result.data;
    return data is Map ? (data['status'] as String? ?? 'pending') : 'pending';
  }

  /// Approves or declines a request. Returns true when this was only the FIRST of two
  /// approvals (a large advance), so the request stays pending for a different admin.
  Future<bool> decide({
    required String requestId,
    required bool approve,
    String? reason,
  }) async {
    final payload = <String, dynamic>{
      'requestId': requestId,
      'approve': approve,
    };
    if (!approve && reason != null && reason.isNotEmpty) {
      payload['reason'] = reason;
    }
    final result = await _functions.httpsCallable('decideDrawRequest').call(payload);
    final data = result.data;
    return data is Map && data['awaitingSecondApproval'] == true;
  }

  /// Records that the advance was paid. [paymentReference] is the reference from the bank
  /// or mobile-money payment; the server refuses a payment with none, one already used,
  /// or one recorded by the person who approved the advance.
  Future<void> disburse(String requestId, String paymentReference) async {
    await _functions
        .httpsCallable('disburseDraw')
        .call({'requestId': requestId, 'paymentReference': paymentReference});
  }

  Stream<List<DrawRequest>> watchHistory() {
    return _collection
        .where('status', whereIn: [
          DrawStatus.approved.name,
          DrawStatus.rejected.name,
        ])
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => DrawRequest.fromMap(d.id, d.data()))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// The most recent requests of any status, newest first (admin Transactions).
  Stream<List<DrawRequest>> watchAll({int limit = 300}) {
    return _collection
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => DrawRequest.fromMap(d.id, d.data())).toList());
  }

  Stream<List<DrawRequest>> watchApprovedPendingDisbursement() {
    return _collection
        .where('status', isEqualTo: DrawStatus.approved.name)
        .where('disbursementStatus', isEqualTo: DisbursementStatus.pending.name)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => DrawRequest.fromMap(d.id, d.data())).toList());
  }
}
