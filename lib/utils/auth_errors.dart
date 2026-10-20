import 'package:firebase_auth/firebase_auth.dart';

/// What to tell someone whose sign-in failed. Only a genuine credential error
/// says "incorrect": blaming the password for a network or server problem sends
/// people off to reset a password that was fine.
String signInErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'Incorrect email or password. Please try again.';
      case 'network-request-failed':
        return 'Could not reach the server. Check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact your HR administrator.';
    }
  }
  return 'Could not sign in right now. Please try again.';
}
