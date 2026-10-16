import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/org_config.dart';
import '../services/org_config_repository.dart';
import 'firebase_providers.dart';

final orgConfigRepositoryProvider = Provider<OrgConfigRepository>(
  (ref) => OrgConfigRepository(
    companyId: requireCompanyId(ref),
    firestore: FirebaseFirestore.instance,
  ),
);

final orgConfigProvider = StreamProvider<OrgConfig>((ref) {
  return ref.watch(orgConfigRepositoryProvider).watch();
});
