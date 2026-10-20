/// One hours record on the sign-off list, with the employee's name filled in by the server.
/// Supervisors cannot read employee records themselves, so this is what they see.
class SignOffRecord {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeNumber;
  final DateTime clockIn;
  final DateTime? clockOut;
  final String source;
  final bool flagged;
  final bool voided;
  final bool reviewed;
  final String? editReason;

  /// False for the person's own hours, and for a record this user typed in or uploaded.
  final bool canSign;

  const SignOffRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeNumber,
    required this.clockIn,
    required this.clockOut,
    required this.source,
    required this.flagged,
    required this.voided,
    required this.reviewed,
    required this.editReason,
    required this.canSign,
  });

  bool get needsSignOff => !reviewed && !voided;

  factory SignOffRecord.fromMap(Map<dynamic, dynamic> m) {
    DateTime? ms(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return SignOffRecord(
      id: m['id'] as String? ?? '',
      employeeId: m['employeeId'] as String? ?? '',
      employeeName: m['employeeName'] as String? ?? '',
      employeeNumber: m['employeeNumber'] as String? ?? '',
      clockIn: ms(m['clockInMs']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      clockOut: ms(m['clockOutMs']),
      source: m['source'] as String? ?? 'manual',
      flagged: m['flagged'] == true,
      voided: m['voided'] == true,
      reviewed: m['reviewed'] == true,
      editReason: m['editReason'] as String?,
      canSign: m['canSign'] == true,
    );
  }
}
