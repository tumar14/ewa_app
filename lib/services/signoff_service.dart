import 'package:cloud_functions/cloud_functions.dart';
import '../models/signoff_record.dart';

/// Sign-off goes through the server (getSignOffDay / signOffSessions) so supervisors can
/// see who worked without any access to employee records, and so nobody signs off their
/// own hours or a record they entered themselves.
class SignOffService {
  final FirebaseFunctions _functions;
  SignOffService({FirebaseFunctions? functions}) : _functions = functions ?? FirebaseFunctions.instance;

  /// Hours that started on [day] (the device's local day).
  Future<List<SignOffRecord>> day(DateTime day) async {
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    final result = await _functions.httpsCallable('getSignOffDay').call({
      'fromMs': from.millisecondsSinceEpoch,
      'toMs': to.millisecondsSinceEpoch,
    });
    final list = (result.data as Map)['sessions'] as List? ?? const [];
    return [for (final s in list) SignOffRecord.fromMap(s as Map)];
  }

  /// Signs off [ids]. Returns how many were signed and the reasons any were refused.
  Future<({int signed, List<String> refused})> signOff(List<String> ids) async {
    final result = await _functions.httpsCallable('signOffSessions').call({'sessionIds': ids});
    final data = result.data as Map;
    return (
      signed: (data['signed'] as num?)?.toInt() ?? 0,
      refused: [for (final r in (data['refused'] as List? ?? const [])) (r as Map)['reason'] as String? ?? ''],
    );
  }
}
