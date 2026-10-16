import 'package:cloud_firestore/cloud_firestore.dart';

enum ClockEventSource { manual, kioskPin, kioskQr, externalImport }

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
  });

  bool get isReviewed => reviewedAt != null;

  Duration get hoursWorked {
    final end = clockOut ?? DateTime.now();
    return end.difference(clockIn);
  }

  factory TimeSession.fromMap(String id, Map<String, dynamic> map) {
    return TimeSession(
      id: id,
      employeeId: map['employeeId'] as String,
      clockIn: (map['clockInTs'] as Timestamp).toDate(),
      clockOut: (map['clockOutTs'] as Timestamp?)?.toDate(),
      source: ClockEventSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => ClockEventSource.manual,
      ),
      flagged: map['flagged'] as bool? ?? false,
      photoUrl: map['photoUrl'] as String?,
      reviewedBy: map['reviewedBy'] as String?,
      reviewedAt: (map['reviewedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'employeeId': employeeId,
        'clockInTs': Timestamp.fromDate(clockIn),
        'clockOutTs': clockOut != null ? Timestamp.fromDate(clockOut!) : null,
        'source': source.name,
        'flagged': flagged,
        'photoUrl': photoUrl,
        'reviewedBy': reviewedBy,
        'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      };
}
