import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/roster_entry.dart';

/// Admin-side CRUD for the pre-loaded employee roster.
///
/// The roster is admin-only (see firestore.rules) — workers never read it.
/// Matching for a claim happens server-side in the `claimSeat` Cloud Function.
class RosterRepository {
  final CollectionReference<Map<String, dynamic>> _collection;

  RosterRepository({required String companyId, FirebaseFirestore? firestore})
      : _collection = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('roster');

  Stream<List<RosterEntry>> watchAll() {
    return _collection.snapshots().map(
          (snap) => snap.docs
              .map((d) => RosterEntry.fromMap(d.id, d.data()))
              .toList()
            ..sort((a, b) => a.employeeNumber.compareTo(b.employeeNumber)),
        );
  }

  /// Creates or overwrites a roster row, keyed by normalized employee number.
  ///
  /// Refuses to overwrite a row that has already been claimed, so re-importing
  /// a roster can never silently detach a worker's existing profile.
  ///
  /// If [entry.claimCode] is blank, a random code is generated — this is the
  /// out-of-band secret HR hands the worker, so it's returned to the caller
  /// to display/print/share (it cannot be read back from Firestore once
  /// dismissed, since these are meant to be treated as one-time credentials).
  Future<String> upsert(RosterEntry entry) async {
    final id = RosterEntry.normalize(entry.employeeNumber);
    final existing = await _collection.doc(id).get();
    if (existing.exists && (existing.data()?['claimed'] as bool? ?? false)) {
      throw StateError(
        'Employee ${entry.employeeNumber} has already claimed their account '
        'and cannot be overwritten.',
      );
    }
    final code = entry.claimCode.trim().isEmpty
        ? RosterEntry.generateCode()
        : RosterEntry.normalizeCode(entry.claimCode);
    await _collection.doc(id).set({
      ...entry.toMap(),
      'employeeNumber': id,
      'claimCode': code,
      ..._freshCodeFields(),
    });
    return code;
  }

  /// Marks a code as just issued: it expires from here (Admin Settings), and any lock
  /// from wrong guesses is cleared.
  Map<String, dynamic> _freshCodeFields() => {
        'claimCodeIssuedAt': FieldValue.serverTimestamp(),
        'claimFailures': 0,
        'claimLockedUntil': null,
      };

  /// Gives an unclaimed seat a new code (the old one stops working) and unlocks it.
  /// Returns the new code to hand to the employee.
  Future<String> reissueCode(String employeeNumber) async {
    final id = RosterEntry.normalize(employeeNumber);
    final doc = await _collection.doc(id).get();
    if (!doc.exists || (doc.data()?['claimed'] as bool? ?? false)) {
      throw StateError('There is no unclaimed seat for $employeeNumber.');
    }
    final code = RosterEntry.generateCode();
    await _collection.doc(id).update({'claimCode': code, ..._freshCodeFields()});
    return code;
  }

  /// Imports many rows, skipping any that are already claimed. Returns the
  /// number of rows written, the employee numbers skipped (already claimed),
  /// and the effective claim code per newly-written row (for distribution).
  Future<({int written, List<String> skipped, Map<String, String> codes})>
      bulkUpsert(List<RosterEntry> entries) async {
    var written = 0;
    final skipped = <String>[];
    final codes = <String, String>{};
    // Chunk into batches of 400 (Firestore hard limit is 500 ops).
    for (var i = 0; i < entries.length; i += 400) {
      final chunk = entries.sublist(
          i, i + 400 > entries.length ? entries.length : i + 400);
      final ids = chunk.map((e) => RosterEntry.normalize(e.employeeNumber));
      final existing = await Future.wait(ids.map((id) => _collection.doc(id).get()));
      final claimed = {
        for (final doc in existing)
          if (doc.exists && (doc.data()?['claimed'] as bool? ?? false)) doc.id,
      };
      final batch = _collection.firestore.batch();
      for (final entry in chunk) {
        final id = RosterEntry.normalize(entry.employeeNumber);
        if (claimed.contains(id)) {
          skipped.add(entry.employeeNumber);
          continue;
        }
        final code = entry.claimCode.trim().isEmpty
            ? RosterEntry.generateCode()
            : RosterEntry.normalizeCode(entry.claimCode);
        batch.set(_collection.doc(id),
            {...entry.toMap(), 'employeeNumber': id, 'claimCode': code, ..._freshCodeFields()});
        codes[id] = code;
        written++;
      }
      await batch.commit();
    }
    return (written: written, skipped: skipped, codes: codes);
  }

  /// Removes an unclaimed roster row. Claimed rows are kept as the audit trail
  /// linking a profile back to the record it was created from.
  Future<void> delete(String employeeNumber) {
    return _collection.doc(RosterEntry.normalize(employeeNumber)).delete();
  }
}
