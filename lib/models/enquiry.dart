import 'package:cloud_firestore/cloud_firestore.dart';

/// A submission from the public website: an employer asking to register, or a
/// general contact message. Written only by the submitEnquiry Cloud Function;
/// only the platform admin can read it. It never creates a company or grants a
/// role by itself.
class Enquiry {
  final String id;
  final bool isEmployerRegistration;
  final bool handled;
  final DateTime createdAt;
  final Map<String, dynamic> data;
  final String? note;

  Enquiry({
    required this.id,
    required this.isEmployerRegistration,
    required this.handled,
    required this.createdAt,
    required this.data,
    this.note,
  });

  factory Enquiry.fromMap(String id, Map<String, dynamic> map) {
    return Enquiry(
      id: id,
      isEmployerRegistration: map['type'] == 'employer_registration',
      handled: map['status'] == 'handled',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      data: map,
      note: map['note'] as String?,
    );
  }

  String _s(String key) => (data[key] as String?) ?? '';

  String get companyName => _s('companyName');
  String get contactName => isEmployerRegistration ? _s('contactName') : _s('name');
  String get contactEmail => isEmployerRegistration ? _s('contactEmail') : _s('email');
  String get contactPhone => isEmployerRegistration ? _s('contactPhone') : _s('phone');
  String get jobTitle => _s('jobTitle');
  String get message => _s('message');
  String get topic => _s('topic');
  int? get employeeCount => (data['employeeCount'] as num?)?.toInt();

  String get title => isEmployerRegistration ? companyName : (topic.isEmpty ? 'Contact message' : topic);
}
