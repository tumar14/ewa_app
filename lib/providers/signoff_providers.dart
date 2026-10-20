import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/signoff_record.dart';
import '../services/signoff_service.dart';

final signOffServiceProvider = Provider((ref) => SignOffService());

/// The hours to sign off for one day. Refresh with ref.invalidate after signing.
final signOffDayProvider = FutureProvider.autoDispose.family<List<SignOffRecord>, DateTime>((ref, day) {
  return ref.watch(signOffServiceProvider).day(day);
});
