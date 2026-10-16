import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/roster_entry.dart';
import 'firebase_providers.dart';

/// All roster rows (admin-only). Sorted by employee number in the repository.
final rosterProvider = StreamProvider<List<RosterEntry>>((ref) {
  return ref.watch(rosterRepositoryProvider).watchAll();
});
