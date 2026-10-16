import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'employee.dart' show DisbursementMethod;

/// A pre-loaded employee record awaiting claim (employee-first onboarding).
///
/// HR uploads these into the private `roster` collection. A worker claims
/// their seat via the `claimSeat` Cloud Function, which materializes the
/// standard employees/{uid} profile from this record and flips [claimed].
///
/// The document id is the normalized (trimmed, upper-cased) employee number,
/// which enforces one roster row per employee number.
class RosterEntry {
  final String employeeNumber; // == document id (normalized)
  final String name;
  final double hourlyRate;
  final String department;
  final String role;
  final DisbursementMethod disbursementMethod;
  final Map<String, String> disbursementDetails;
  final bool claimed;
  final String? claimedByUid;
  final DateTime? claimedAt;

  /// One-time code HR hands to the worker out-of-band (payslip, SMS, printed
  /// handout) — the third claim factor alongside employee number and name.
  /// Employee number and name alone are not secret (coworkers know both), so
  /// this is what actually prevents someone claiming a colleague's seat.
  final String claimCode;

  RosterEntry({
    required this.employeeNumber,
    required this.name,
    required this.hourlyRate,
    required this.claimCode,
    this.department = '',
    this.role = 'worker',
    this.disbursementMethod = DisbursementMethod.bankTransfer,
    this.disbursementDetails = const {},
    this.claimed = false,
    this.claimedByUid,
    this.claimedAt,
  });

  /// Normalizes an employee number for use as the document id / match key.
  static String normalize(String employeeNumber) =>
      employeeNumber.trim().toUpperCase();

  /// Normalizes a claim code for comparison (case/space insensitive).
  static String normalizeCode(String code) =>
      code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no 0/O/1/I/L

  /// Generates a random 6-character claim code, avoiding characters that are
  /// easily confused when HR reads or types it out (0/O, 1/I/L).
  static String generateCode([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
        6, (_) => _codeAlphabet[rng.nextInt(_codeAlphabet.length)]).join();
  }

  factory RosterEntry.fromMap(String id, Map<String, dynamic> map) {
    return RosterEntry(
      employeeNumber: map['employeeNumber'] as String? ?? id,
      name: map['name'] as String? ?? '',
      hourlyRate: (map['hourlyRate'] as num?)?.toDouble() ?? 0,
      department: map['department'] as String? ?? '',
      role: map['role'] as String? ?? 'worker',
      disbursementMethod: DisbursementMethod.values.firstWhere(
        (e) => e.name == map['disbursementMethod'],
        orElse: () => DisbursementMethod.bankTransfer,
      ),
      disbursementDetails: Map<String, String>.from(
        map['disbursementDetails'] as Map? ?? {},
      ),
      claimCode: map['claimCode'] as String? ?? '',
      claimed: map['claimed'] as bool? ?? false,
      claimedByUid: map['claimedByUid'] as String?,
      claimedAt: (map['claimedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'employeeNumber': employeeNumber,
        'name': name,
        'hourlyRate': hourlyRate,
        'department': department,
        'role': role,
        'disbursementMethod': disbursementMethod.name,
        'disbursementDetails': disbursementDetails,
        'claimCode': claimCode,
        'claimed': claimed,
        'claimedByUid': claimedByUid,
      };
}
