import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/payroll_run.dart';
import 'firebase_providers.dart';

final recentPayrollRunsProvider = StreamProvider<List<PayrollRun>>((ref) {
  return ref.watch(payrollRepositoryProvider).watchRecent();
});
