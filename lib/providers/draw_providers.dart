import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/draw_request.dart';
import 'firebase_providers.dart';

final employeeDrawsProvider =
    StreamProvider.family<List<DrawRequest>, String>((ref, employeeId) {
  return ref.watch(drawRepositoryProvider).watchForEmployee(employeeId);
});

/// Draws still outstanding (not yet settled by a payroll run) — use this
/// for cap/eligibility math, not the full history above.
final outstandingDrawsProvider =
    StreamProvider.family<List<DrawRequest>, String>((ref, employeeId) {
  return ref.watch(drawRepositoryProvider).watchOutstandingForEmployee(employeeId);
});

final pendingDrawsProvider = StreamProvider<List<DrawRequest>>((ref) {
  return ref.watch(drawRepositoryProvider).watchPending();
});

final drawHistoryProvider = StreamProvider<List<DrawRequest>>((ref) {
  return ref.watch(drawRepositoryProvider).watchHistory();
});

final allDrawsProvider = StreamProvider<List<DrawRequest>>((ref) {
  return ref.watch(drawRepositoryProvider).watchAll();
});

final approvedPendingDisbursementProvider = StreamProvider<List<DrawRequest>>((ref) {
  return ref.watch(drawRepositoryProvider).watchApprovedPendingDisbursement();
});

final pendingDrawsCountProvider = Provider<int>((ref) {
  return ref.watch(pendingDrawsProvider).valueOrNull?.length ?? 0;
});

final pendingDisbursementCountProvider = Provider<int>((ref) {
  return ref.watch(approvedPendingDisbursementProvider).valueOrNull?.length ?? 0;
});
