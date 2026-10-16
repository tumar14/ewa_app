import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/payroll_run.dart';

class PayrollRepository {
  final CollectionReference<Map<String, dynamic>> _collection;
  final FirebaseFunctions _functions;

  PayrollRepository({
    required String companyId,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _collection = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('payroll_runs'),
        _functions = functions ?? FirebaseFunctions.instance;

  Stream<List<PayrollRun>> watchRecent({int limit = 12}) {
    return _collection
        .orderBy('cycleEnd', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => PayrollRun.fromMap(d.id, d.data())).toList());
  }

  /// Triggers the `runPayroll` Cloud Function: resets accrual and deducts
  /// outstanding draws for every employee (spec section 4 step 4 / section 9).
  Future<void> triggerRun() {
    final callable = _functions.httpsCallable('runPayroll');
    return callable.call();
  }
}
