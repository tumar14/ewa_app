import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/employee.dart';
import 'firebase_providers.dart';

final allEmployeesProvider = StreamProvider<List<Employee>>((ref) {
  return ref.watch(employeeRepositoryProvider).watchAll();
});

final employeeByIdProvider =
    StreamProvider.family<Employee?, String>((ref, employeeId) {
  return ref.watch(employeeRepositoryProvider).watch(employeeId);
});
