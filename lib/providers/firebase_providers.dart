import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/employee_repository.dart';
import '../services/time_session_repository.dart';
import '../services/draw_repository.dart';
import '../services/settings_repository.dart';
import '../services/payroll_repository.dart';
import '../services/settlement_repository.dart';
import '../services/audit_log_repository.dart';
import '../services/roster_repository.dart';
import '../services/claim_service.dart';
import '../services/platform_admin_service.dart';
import 'auth_providers.dart';

/// Every company-scoped repository provider below reads this instead of
/// taking a companyId parameter itself — so every existing screen/provider
/// that does `ref.watch(employeeRepositoryProvider)` etc. keeps working
/// unchanged, automatically scoped to whichever company the signed-in user
/// resolved to. Throws if read before [myCompanyIdProvider] resolves; that
/// should never happen because AuthGate (lib/main.dart) never builds the
/// part of the widget tree that reads these until a company is known.
String requireCompanyId(Ref ref) {
  final companyId = ref.watch(myCompanyIdProvider);
  if (companyId == null) {
    throw StateError(
      'A company-scoped repository was read before a company was resolved.',
    );
  }
  return companyId;
}

final authServiceProvider = Provider((ref) => AuthService());
final claimServiceProvider = Provider((ref) => ClaimService());
final platformAdminServiceProvider = Provider((ref) => PlatformAdminService());

final employeeRepositoryProvider = Provider(
  (ref) => EmployeeRepository(companyId: requireCompanyId(ref)),
);
final rosterRepositoryProvider = Provider(
  (ref) => RosterRepository(companyId: requireCompanyId(ref)),
);
final timeSessionRepositoryProvider = Provider(
  (ref) => TimeSessionRepository(companyId: requireCompanyId(ref)),
);
final drawRepositoryProvider = Provider(
  (ref) => DrawRepository(companyId: requireCompanyId(ref)),
);
final settingsRepositoryProvider = Provider(
  (ref) => SettingsRepository(companyId: requireCompanyId(ref)),
);
final payrollRepositoryProvider = Provider(
  (ref) => PayrollRepository(companyId: requireCompanyId(ref)),
);
final settlementRepositoryProvider = Provider(
  (ref) => SettlementRepository(companyId: requireCompanyId(ref)),
);
final auditLogRepositoryProvider = Provider(
  (ref) => AuditLogRepository(companyId: requireCompanyId(ref)),
);
