/// A tenant on the platform. Public-read directory info only (name, short
/// code, branding, HR contact, currency) — no employee/payroll data lives
/// here, that's all under `companies/{id}/...` subcollections which are
/// never publicly readable.
class Company {
  final String id;
  final String name;
  final String shortCode;
  final String? logoUrl;
  final String hrEmail;
  final String hrPhone;
  final String currency;
  final bool active;

  Company({
    required this.id,
    required this.name,
    required this.shortCode,
    this.logoUrl,
    this.hrEmail = '',
    this.hrPhone = '',
    this.currency = 'SZL',
    this.active = true,
  });

  factory Company.fromMap(String id, Map<String, dynamic> map) {
    return Company(
      id: id,
      name: map['name'] as String? ?? '',
      shortCode: map['shortCode'] as String? ?? '',
      logoUrl: map['logoUrl'] as String?,
      hrEmail: map['hrEmail'] as String? ?? '',
      hrPhone: map['hrPhone'] as String? ?? '',
      currency: map['currency'] as String? ?? 'SZL',
      active: map['active'] as bool? ?? true,
    );
  }
}
