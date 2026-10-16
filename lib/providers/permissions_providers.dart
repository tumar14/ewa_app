import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_permissions.dart';
import '../services/permissions_repository.dart';
import 'firebase_providers.dart';

final permissionsRepositoryProvider = Provider<PermissionsRepository>(
  (ref) => PermissionsRepository(
    companyId: requireCompanyId(ref),
    firestore: FirebaseFirestore.instance,
  ),
);

final appPermissionsProvider = StreamProvider<AppPermissions>((ref) {
  return ref.watch(permissionsRepositoryProvider).watch();
});
