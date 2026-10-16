import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audit_log_entry.dart';
import 'firebase_providers.dart';

final auditLogProvider = StreamProvider<List<AuditLogEntry>>((ref) {
  return ref.watch(auditLogRepositoryProvider).watchRecent();
});
