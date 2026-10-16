import 'package:cloud_functions/cloud_functions.dart';

/// Thrown when a seat claim fails, carrying a worker-friendly message.
class ClaimException implements Exception {
  final String message;
  ClaimException(this.message);
  @override
  String toString() => message;
}

/// Worker-facing entry point for employee-first onboarding.
///
/// Delegates entirely to the `claimSeat` Cloud Function — the match against
/// the private roster, the Auth-user creation and the profile materialization
/// all happen server-side, so no roster data ever reaches the device.
class ClaimService {
  final FirebaseFunctions _functions;

  ClaimService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Attempts to claim a roster seat. On success the Auth account exists and
  /// the caller should sign in with [email] / [password]. Throws
  /// [ClaimException] with a display-ready message on any failure.
  Future<void> claim({
    required String companyId,
    required String employeeNumber,
    required String fullName,
    required String claimCode,
    required String email,
    required String password,
  }) async {
    try {
      final callable = _functions.httpsCallable('claimSeat');
      await callable.call({
        'companyId': companyId,
        'employeeNumber': employeeNumber,
        'fullName': fullName,
        'claimCode': claimCode,
        'email': email,
        'password': password,
      });
    } on FirebaseFunctionsException catch (e) {
      throw ClaimException(_messageFor(e));
    } catch (_) {
      throw ClaimException(
          'Something went wrong. Please check your connection and try again.');
    }
  }

  String _messageFor(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'permission-denied':
      case 'invalid-argument':
      case 'already-exists':
        // These carry a safe, specific message straight from the function.
        return e.message ??
            'We couldn\'t match those details. Please check with HR.';
      case 'not-found':
      case 'unimplemented':
        // Function not deployed (e.g. still on Spark plan). Never fall back to
        // a client-side match — that would expose the roster.
        return 'Account claiming isn\'t available yet. Please contact HR to '
            'set up your login.';
      default:
        return 'Something went wrong. Please try again or contact HR.';
    }
  }
}
