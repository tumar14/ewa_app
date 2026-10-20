import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/employee.dart';
import '../utils/pin_hasher.dart';

class EmployeeRepository {
  final CollectionReference<Map<String, dynamic>> _collection;

  EmployeeRepository({required String companyId, FirebaseFirestore? firestore})
      : _collection = (firestore ?? FirebaseFirestore.instance)
            .collection('companies')
            .doc(companyId)
            .collection('employees');

  Stream<Employee?> watch(String employeeId) {
    return _collection.doc(employeeId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final e = Employee.fromMap(doc.id, doc.data()!);
      return e.active ? e : null;
    });
  }

  Future<Employee?> get(String employeeId) async {
    final doc = await _collection.doc(employeeId).get();
    return doc.exists ? Employee.fromMap(doc.id, doc.data()!) : null;
  }

  Stream<List<Employee>> watchAll() {
    return _collection.snapshots().map(
          (snap) => snap.docs
              .map((doc) => Employee.fromMap(doc.id, doc.data()))
              .where((e) => e.active)
              .toList(),
        );
  }

  /// Creates a Firebase Auth user + Firestore employee doc.
  ///
  /// Uses a secondary Firebase App instance so the current admin session is
  /// not signed out (Spark plan has no Cloud Functions).
  ///
  /// New employees are flagged mustChangePassword: true so they are forced
  /// to set their own password on first login.
  Future<String> create({
    required String name,
    required String email,
    required String temporaryPassword,
    required double hourlyRate,
    required String employeeNumber,
    String role = 'worker',
    String department = '',
    String? pin,
    DisbursementMethod disbursementMethod = DisbursementMethod.bankTransfer,
    Map<String, String> disbursementDetails = const {},
  }) async {
    const appName = 'ewa_employee_creator';
    FirebaseApp secondaryApp;
    try {
      secondaryApp = Firebase.app(appName);
    } catch (_) {
      secondaryApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
    }

    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    if (secondaryAuth.currentUser != null) await secondaryAuth.signOut();

    final cred = await secondaryAuth.createUserWithEmailAndPassword(
      email: email,
      password: temporaryPassword,
    );
    final uid = cred.user!.uid;
    await secondaryAuth.signOut();

    String? storedPin;
    String? storedSalt;
    if (pin != null && pin.isNotEmpty) {
      storedSalt = PinHasher.generateSalt();
      storedPin = PinHasher.hashPin(pin, storedSalt);
    }

    await _collection.doc(uid).set({
      // The server's time and the admin's id: firestore.rules require them, and they let the
      // audit log name who added this person and stop a start date being backdated.
      'createdAt': FieldValue.serverTimestamp(),
      ..._editStamp(),
      'name': name,
      'email': email,
      'department': department,
      'employeeNumber': employeeNumber,
      'hourlyRate': hourlyRate,
      'role': role,
      'pin': storedPin,
      'pinSalt': storedSalt,
      'qrCode': null,
      'disbursementMethod': disbursementMethod.name,
      'disbursementDetails': disbursementDetails,
      'active': true,
      'mustChangePassword': true,
      'consentedAt': null,
    });

    return uid;
  }

  /// Marks the employee inactive in Firestore.
  Future<void> deactivate(String employeeId) {
    return _collection.doc(employeeId).update({'active': false, ..._editStamp()});
  }

  /// Who made this edit and when. firestore.rules insist on it for every admin change.
  Map<String, dynamic> _editStamp() => {
        'lastEditedBy': FirebaseAuth.instance.currentUser!.uid,
        'lastEditedAt': FieldValue.serverTimestamp(),
      };

  /// Updates mutable profile fields.
  ///
  /// Pass [rawPin] to change the PIN (hashed before storing).
  /// Pass an empty string for [rawPin] to clear the PIN.
  /// Omit [rawPin] (null) to leave the existing PIN unchanged.
  Future<void> update(Employee employee, {String? rawPin}) async {
    final data = employee.toMap();

    if (rawPin != null) {
      if (rawPin.isEmpty) {
        data['pin'] = null;
        data['pinSalt'] = null;
      } else {
        final salt = PinHasher.generateSalt();
        data['pin'] = PinHasher.hashPin(rawPin, salt);
        data['pinSalt'] = salt;
      }
    }

    return _collection.doc(employee.id).update({...data, ..._editStamp()});
  }

  Future<void> updateFcmToken(String employeeId, String token) {
    return _collection.doc(employeeId).update({'fcmToken': token});
  }

  /// Records the employee's consent timestamp so the consent gate is cleared.
  Future<void> acceptConsent(String employeeId) {
    return _collection.doc(employeeId).update({
      'consentedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Clears the first-login password-change requirement.
  Future<void> clearMustChangePassword(String employeeId) {
    return _collection
        .doc(employeeId)
        .update({'mustChangePassword': false});
  }
}
