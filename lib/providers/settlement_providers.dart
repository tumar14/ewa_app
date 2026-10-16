import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settlement.dart';
import 'firebase_providers.dart';

final settlementsProvider = StreamProvider<List<Settlement>>((ref) {
  return ref.watch(settlementRepositoryProvider).watchAll();
});

final settlementProvider = StreamProvider.family<Settlement?, String>((ref, id) {
  return ref.watch(settlementRepositoryProvider).watchOne(id);
});

final settlementItemsProvider =
    StreamProvider.family<List<SettlementItem>, String>((ref, id) {
  return ref.watch(settlementRepositoryProvider).watchItems(id);
});

final settlementExceptionsProvider =
    StreamProvider.family<List<SettlementException>, String>((ref, id) {
  return ref.watch(settlementRepositoryProvider).watchExceptions(id);
});
