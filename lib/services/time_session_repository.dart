import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import '../models/time_session.dart';

class TimeSessionRepository {
  final CollectionReference<Map<String, dynamic>> _collection;
  final FirebaseStorage _storage;

  final String _companyId;

  TimeSessionRepository({
    required String companyId,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _companyId = companyId,
        _collection = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('time_sessions'),
        _storage = storage ?? FirebaseStorage.instance;

  /// Sessions for one employee within the current pay cycle, newest first.
  Stream<List<TimeSession>> watchForEmployee(
    String employeeId, {
    required DateTime cycleStart,
  }) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .where('clockInTs', isGreaterThanOrEqualTo: Timestamp.fromDate(cycleStart))
        .orderBy('clockInTs', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TimeSession.fromMap(d.id, d.data())).toList());
  }

  /// The open (not yet clocked out) session for an employee, if any.
  Stream<TimeSession?> watchOpenSession(String employeeId) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .where('clockOutTs', isNull: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : TimeSession.fromMap(snap.docs.first.id, snap.docs.first.data()));
  }

  /// How close together two different employees' clock-ins have to be
  /// before we treat it as a possible buddy-punch and flag both records
  /// for supervisor review (spec section 6, buddy-punching mitigations).
  static const _suspiciousWindow = Duration(seconds: 15);

  /// Clocks the employee in. If another employee clocked in within
  /// [_suspiciousWindow] of this punch (e.g. two badges tapped back-to-back
  /// at a shared kiosk), both sessions are flagged for the supervisor
  /// daily sign-off screen. Returns the new session's id and whether it
  /// was flagged, so the caller can attach a punch photo and warn the
  /// kiosk operator.
  ///
  /// Buddy-punch detection requires reading other employees' sessions, which
  /// Firestore rules only permit for admins. For worker-initiated punches the
  /// cross-employee query is skipped gracefully; the flag will be set by the
  /// supervisor sign-off screen (or a Cloud Function when the project upgrades
  /// to Blaze plan).
  Future<({String sessionId, bool flagged})> clockIn(TimeSession session) async {
    bool flagged = false;
    List<TimeSession> otherNearbyPunches = [];

    try {
      final windowStart = session.clockIn.subtract(_suspiciousWindow);
      final windowEnd = session.clockIn.add(_suspiciousWindow);

      final nearbySnap = await _collection
          .where('clockInTs', isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
          .where('clockInTs', isLessThanOrEqualTo: Timestamp.fromDate(windowEnd))
          .get();

      otherNearbyPunches = nearbySnap.docs
          .map((d) => TimeSession.fromMap(d.id, d.data()))
          .where((s) => s.employeeId != session.employeeId)
          .toList();

      flagged = otherNearbyPunches.isNotEmpty;
    } on FirebaseException {
      // Non-admin workers cannot read other employees' sessions.
      // Buddy-punch detection is deferred to supervisor sign-off.
    }

    final data = session.toMap();
    data['flagged'] = flagged;
    final newDoc = await _collection.add(data);

    if (flagged && otherNearbyPunches.isNotEmpty) {
      try {
        final batch = _collection.firestore.batch();
        batch.update(_collection.doc(newDoc.id), {'flagged': true});
        for (final other in otherNearbyPunches) {
          batch.update(_collection.doc(other.id), {'flagged': true});
        }
        await batch.commit();
      } on FirebaseException {
        // Admin-only; silently deferred.
      }
    }

    return (sessionId: newDoc.id, flagged: flagged);
  }

  Future<void> clockOut(String sessionId, DateTime clockOutTs) {
    return _collection
        .doc(sessionId)
        .update({'clockOutTs': Timestamp.fromDate(clockOutTs)});
  }

  Future<void> flag(String sessionId, bool flagged) {
    return _collection.doc(sessionId).update({'flagged': flagged});
  }

  /// Records the photo captured at a kiosk punch (buddy-punching
  /// mitigation, spec section 6) — reviewable later on dispute.
  Future<void> setPunchPhoto(String sessionId, String photoUrl) {
    return _collection.doc(sessionId).update({'photoUrl': photoUrl});
  }

  /// Uploads a kiosk punch photo to Storage and links it to the session.
  /// Uses bytes (not dart:io File) so this works on web too, per the
  /// spec's "Android + iOS + Web from one codebase" platform target.
  /// Photo failures never block the punch — call this after clockIn/Out
  /// already succeeded and swallow errors at the call site if needed.
  Future<void> uploadPunchPhoto(String sessionId, XFile photo) async {
    final bytes = await photo.readAsBytes();
    final ref = _storage.ref('punches/$_companyId/$sessionId.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await setPunchPhoto(sessionId, url);
  }

  /// All punches on [day] across every employee, for the supervisor daily
  /// sign-off screen (spec section 6). Newest first.
  Stream<List<TimeSession>> watchForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _collection
        .where('clockInTs', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('clockInTs', isLessThan: Timestamp.fromDate(end))
        .orderBy('clockInTs', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TimeSession.fromMap(d.id, d.data())).toList());
  }

  /// Every session for one employee, newest first — for the admin
  /// per-employee time-session detail screen (drill-down from Workforce).
  Stream<List<TimeSession>> watchAllForEmployee(String employeeId) {
    return _collection
        .where('employeeId', isEqualTo: employeeId)
        .orderBy('clockInTs', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TimeSession.fromMap(d.id, d.data())).toList());
  }

  /// Supervisor daily sign-off: stamps a punch as reviewed. Bulk sign-off
  /// (a whole day) calls this once per session via a batch from the caller.
  Future<void> markReviewed(String sessionId, String reviewerId) {
    return _collection.doc(sessionId).update({
      'reviewedBy': reviewerId,
      'reviewedAt': Timestamp.now(),
    });
  }

  /// Signs off every not-yet-reviewed session in [sessions] in one batch —
  /// used by the "sign off day" bulk action.
  Future<void> markReviewedBatch(List<TimeSession> sessions, String reviewerId) {
    final batch = _collection.firestore.batch();
    final now = Timestamp.now();
    for (final s in sessions) {
      if (s.isReviewed) continue;
      batch.update(_collection.doc(s.id), {
        'reviewedBy': reviewerId,
        'reviewedAt': now,
      });
    }
    return batch.commit();
  }
}
