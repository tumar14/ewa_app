import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/rate_matrix.dart';

class RatesRepository {
  final DocumentReference<Map<String, dynamic>> _doc;

  RatesRepository({required String companyId, FirebaseFirestore? firestore})
      : _doc = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('settings')
            .doc('rates');

  Stream<RateMatrix> watch() =>
      _doc.snapshots().map((snap) => RateMatrix.fromMap(snap.data()));

  Future<RateMatrix> get() async {
    final snap = await _doc.get();
    return RateMatrix.fromMap(snap.data());
  }

  Future<void> save(RateMatrix matrix) => _doc.set(matrix.toMap());
}
