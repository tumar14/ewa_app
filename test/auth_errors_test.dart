import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ewa_app/utils/auth_errors.dart';

void main() {
  String message(String code) => signInErrorMessage(FirebaseAuthException(code: code));

  test('real credential errors say the email or password is incorrect', () {
    for (final code in ['invalid-credential', 'wrong-password', 'user-not-found', 'invalid-email']) {
      expect(message(code), startsWith('Incorrect email or password'), reason: code);
    }
  });

  test('network and server problems are not blamed on the password', () {
    expect(message('network-request-failed'), contains('Could not reach the server'));
    expect(message('internal-error'), isNot(contains('Incorrect')));
    expect(signInErrorMessage(Exception('boom')), isNot(contains('Incorrect')));
  });

  test('other known cases get their own message', () {
    expect(message('too-many-requests'), contains('Too many attempts'));
    expect(message('user-disabled'), contains('disabled'));
  });
}
