import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rate_matrix.dart';
import '../services/rates_repository.dart';
import 'firebase_providers.dart';

final ratesRepositoryProvider = Provider<RatesRepository>(
  (ref) => RatesRepository(
    companyId: requireCompanyId(ref),
    firestore: FirebaseFirestore.instance,
  ),
);

final rateMatrixProvider = StreamProvider<RateMatrix>((ref) {
  return ref.watch(ratesRepositoryProvider).watch();
});
