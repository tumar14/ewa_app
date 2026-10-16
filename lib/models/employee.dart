import 'package:cloud_firestore/cloud_firestore.dart';

enum ClockSource { manual, kioskPin, kioskQr, externalImport }

enum DisbursementMethod { bankTransfer, mobileMoney, cash }

class Employee {
  final String id;
  final String name;
  final String email;
  final String department;
  final String employeeNumber;
  final double hourlyRate;
  final String? pin;
  final String? pinSalt; // null → pin is stored as plaintext (legacy)
  final String? qrCode;
  final String role; // 'worker' | 'supervisor' | 'admin'
  final DisbursementMethod disbursementMethod;
  final Map<String, String> disbursementDetails;
  final String? fcmToken;
  final bool active;
  final bool mustChangePassword;
  final DateTime? consentedAt;

  Employee({
    required this.id,
    required this.name,
    required this.hourlyRate,
    required this.role,
    this.email = '',
    this.department = '',
    this.employeeNumber = '',
    this.pin,
    this.pinSalt,
    this.qrCode,
    this.disbursementMethod = DisbursementMethod.bankTransfer,
    this.disbursementDetails = const {},
    this.fcmToken,
    this.active = true,
    this.mustChangePassword = false,
    this.consentedAt,
  });

  factory Employee.fromMap(String id, Map<String, dynamic> map) {
    return Employee(
      id: id,
      name: map['name'] as String,
      email: map['email'] as String? ?? '',
      department: map['department'] as String? ?? '',
      employeeNumber: map['employeeNumber'] as String? ?? '',
      hourlyRate: (map['hourlyRate'] as num).toDouble(),
      role: map['role'] as String? ?? 'worker',
      pin: map['pin'] as String?,
      pinSalt: map['pinSalt'] as String?,
      qrCode: map['qrCode'] as String?,
      disbursementMethod: DisbursementMethod.values.firstWhere(
        (e) => e.name == map['disbursementMethod'],
        orElse: () => DisbursementMethod.bankTransfer,
      ),
      disbursementDetails: Map<String, String>.from(
        map['disbursementDetails'] as Map? ?? {},
      ),
      fcmToken: map['fcmToken'] as String?,
      active: map['active'] as bool? ?? true,
      mustChangePassword: map['mustChangePassword'] as bool? ?? false,
      consentedAt: (map['consentedAt'] as Timestamp?)?.toDate(),
    );
  }

  // Excluded fields — managed by dedicated repository methods only:
  //   pin, pinSalt        → EmployeeRepository.create() / update(rawPin:)
  //   mustChangePassword  → EmployeeRepository.clearMustChangePassword()
  //   consentedAt         → EmployeeRepository.acceptConsent()
  // Keeping them out of toMap() prevents accidental resets on every form save.
  Map<String, dynamic> toMap() => {
        'name': name,
        'department': department,
        'employeeNumber': employeeNumber,
        'hourlyRate': hourlyRate,
        'role': role,
        'qrCode': qrCode,
        'disbursementMethod': disbursementMethod.name,
        'disbursementDetails': disbursementDetails,
        'active': active,
      };
}
