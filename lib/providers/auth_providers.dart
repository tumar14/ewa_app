import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/employee.dart';
import 'firebase_providers.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// The signed-in user's platform identity, resolved from Firebase Auth
/// custom claims (`companyId`, `platformAdmin`) set by claimSeat/
/// createEmployee/createCompany — not a Firestore doc. Claims are what let
/// the client know which company subcollection to read *before* it can even
/// construct that path. `role` is deliberately NOT part of this — it stays a
/// live Firestore read (see EmployeeRepository) so a demotion/deactivation
/// takes effect on the very next request, not on next token refresh.
class Tenant {
  final String? companyId;
  final bool platformAdmin;
  const Tenant({this.companyId, this.platformAdmin = false});
}

/// Force-refreshes the ID token on every auth-state change so a just-claimed
/// or just-created account picks up its claims immediately, without waiting
/// for the SDK's normal ~1hr token refresh cycle.
final tenantProvider = FutureProvider<Tenant?>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;
  final tokenResult = await user.getIdTokenResult(true);
  final claims = tokenResult.claims ?? const {};
  return Tenant(
    companyId: claims['companyId'] as String?,
    platformAdmin: claims['platformAdmin'] == true,
  );
});

/// Null while loading, signed out, or for a platform admin (who belongs to
/// no company). Company-scoped repository providers read this and throw if
/// ever watched before it resolves — AuthGate gates the whole app on
/// [tenantProvider] first, so that should never happen in practice.
final myCompanyIdProvider = Provider<String?>((ref) {
  return ref.watch(tenantProvider).valueOrNull?.companyId;
});

final isPlatformAdminProvider = Provider<bool>((ref) {
  return ref.watch(tenantProvider).valueOrNull?.platformAdmin ?? false;
});

/// The signed-in employee's own profile (role, hourly rate, etc), scoped to
/// their company. Null while signed out, before a company is resolved, or
/// before the employees/{uid} doc loads.
final currentEmployeeProvider = StreamProvider<Employee?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  final companyId = ref.watch(myCompanyIdProvider);
  if (companyId == null) return Stream.value(null);
  return ref.watch(employeeRepositoryProvider).watch(user.uid);
});
