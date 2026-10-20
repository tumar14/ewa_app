import 'package:cloud_firestore/cloud_firestore.dart';

/// Where a record came from. `adminEdit` and `externalImport` are changes made
/// after the fact (typed in or uploaded by an admin); firestore.rules only allow
/// them when the company's settings do, and each one names who made it.
enum ClockEventSource { manual, kioskPin, kioskQr, externalImport, adminEdit }

class TimeSession {
  final String id;
  final String employeeId;
  final DateTime clockIn;
  final DateTime? clockOut;
  final ClockEventSource source;
  final bool flagged; // e.g. suspiciously back-to-back punches
  final String? photoUrl; // kiosk punch photo (buddy-punching mitigation)
  final String? reviewedBy; // supervisor daily sign-off (spec section 6)
  final DateTime? reviewedAt;

  /// A record an admin cancelled. It stays in the history but never counts.
  final bool voided;
  final String? editedBy;
  final DateTime? editedAt;
  final String? editReason;
  final String? importBatchId;

  TimeSession({
    required this.id,
    required this.employeeId,
    required this.clockIn,
    required this.source,
    this.clockOut,
    this.flagged = false,
    this.photoUrl,
    this.reviewedBy,
    this.reviewedAt,
    this.voided = false,
    this.editedBy,
    this.editedAt,
    this.editReason,
    this.importBatchId,
  });

  bool get isReviewed => reviewedAt != null;

  /// Typed in, corrected or uploaded rather than punched.
  bool get isManualChange =>
      source == ClockEventSource.adminEdit || source == ClockEventSource.externalImport;

  Duration get hoursWorked {
    final end = clockOut ?? DateTime.now();
    return end.difference(clockIn);
  }

  factory TimeSession.fromMap(String id, Map<String, dynamic> map) {
    return TimeSession(
      id: id,
      employeeId: map['employeeId'] as String,
      // A just-written punch has no server time yet for a moment; treat it as now.
      clockIn: (map['clockInTs'] as Timestamp?)?.toDate() ?? DateTime.now(),
      clockOut: (map['clockOutTs'] as Timestamp?)?.toDate(),
      source: ClockEventSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => ClockEventSource.manual,
      ),
      flagged: map['flagged'] as bool? ?? false,
      photoUrl: map['photoUrl'] as String?,
      reviewedBy: map['reviewedBy'] as String?,
      reviewedAt: (map['reviewedAt'] as Timestamp?)?.toDate(),
      voided: map['voided'] == true,
      editedBy: map['editedBy'] as String?,
      editedAt: (map['editedAt'] as Timestamp?)?.toDate(),
      editReason: map['editReason'] as String?,
      importBatchId: map['importBatchId'] as String?,
    );
  }

  /// The fields of a new punch. A worker's own punch may contain only these eight
  /// (firestore.rules), so the edit fields are added only when they are set.
  Map<String, dynamic> toMap() => {
        'employeeId': employeeId,
        'clockInTs': Timestamp.fromDate(clockIn),
        'clockOutTs': clockOut != null ? Timestamp.fromDate(clockOut!) : null,
        'source': source.name,
        'flagged': flagged,
        'photoUrl': photoUrl,
        'reviewedBy': reviewedBy,
        'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
        if (voided) 'voided': true,
        if (editedBy != null) 'editedBy': editedBy,
        if (editReason != null) 'editReason': editReason,
        if (importBatchId != null) 'importBatchId': importBatchId,
      };
}
