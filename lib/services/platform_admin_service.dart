import 'package:cloud_functions/cloud_functions.dart';
import '../models/platform_overview.dart';

/// Thrown when creating a company fails, carrying a display-ready message.
class CreateCompanyException implements Exception {
  final String message;
  CreateCompanyException(this.message);
  @override
  String toString() => message;
}

/// What the server reports after a bank payment is recorded. The platform
/// admin never reads company data, so this is all they see of a settlement.
class RecordedPayment {
  final bool duplicate;
  final String status;
  final int receivedMinor;
  final int outstandingMinor;

  RecordedPayment({
    required this.duplicate,
    required this.status,
    required this.receivedMinor,
    required this.outstandingMinor,
  });
}

/// Platform-admin-only actions that must run server-side with the Admin
/// SDK (creating the company's first Auth user + setting custom claims).
/// Simple company edits (name/branding/active toggle) go straight through
/// [CompanyRepository] instead — see its doc comment for why that's safe.
class PlatformAdminService {
  final FirebaseFunctions _functions;

  PlatformAdminService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Counts per company (employees, advances, what is owed). Numbers only: the
  /// server never returns a person's name or an individual amount.
  Future<PlatformOverview> platformOverview() async {
    try {
      final result = await _functions.httpsCallable('platformOverview').call();
      return PlatformOverview.fromMap(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw CreateCompanyException(e.message ?? 'Could not load the overview. Please try again.');
    } catch (_) {
      throw CreateCompanyException('Could not load the overview. Please check your connection and try again.');
    }
  }

  /// Records a verified incoming bank payment against a company's settlement
  /// reference. [providerTransactionId] is the bank's own id for the line, so
  /// submitting the same line twice is counted once.
  Future<RecordedPayment> recordSettlementPayment({
    required String shortCode,
    required String reference,
    required int amountMinor,
    required String currency,
    required String providerTransactionId,
  }) async {
    try {
      final result = await _functions.httpsCallable('recordSettlementPayment').call({
        'shortCode': shortCode,
        'reference': reference,
        'amountMinor': amountMinor,
        'currency': currency,
        'providerTransactionId': providerTransactionId,
      });
      final data = result.data as Map;
      return RecordedPayment(
        duplicate: data['duplicate'] as bool,
        status: data['status'] as String,
        receivedMinor: (data['receivedMinor'] as num).toInt(),
        outstandingMinor: (data['outstandingMinor'] as num).toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw CreateCompanyException(
        e.message ?? 'Could not record the payment. Please try again.',
      );
    } catch (_) {
      throw CreateCompanyException(
        'Something went wrong. Please check your connection and try again.',
      );
    }
  }

  /// Creates a new company shell plus its first admin employee. Returns
  /// the new company's id and shareable short code.
  Future<({String companyId, String shortCode})> createCompany({
    required String name,
    required String hrEmail,
    required String hrPhone,
    required String currency,
    required String adminName,
    required String adminEmail,
    required String adminTemporaryPassword,
  }) async {
    try {
      final callable = _functions.httpsCallable('createCompany');
      final result = await callable.call({
        'name': name,
        'hrEmail': hrEmail,
        'hrPhone': hrPhone,
        'currency': currency,
        'adminName': adminName,
        'adminEmail': adminEmail,
        'adminTemporaryPassword': adminTemporaryPassword,
      });
      final data = result.data as Map;
      return (
        companyId: data['companyId'] as String,
        shortCode: data['shortCode'] as String,
      );
    } on FirebaseFunctionsException catch (e) {
      throw CreateCompanyException(
        e.message ?? 'Could not create the company. Please try again.',
      );
    } catch (_) {
      throw CreateCompanyException(
        'Something went wrong. Please check your connection and try again.',
      );
    }
  }
}
