import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth;

  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> reauthenticate(String email, String password) {
    final credential =
        EmailAuthProvider.credential(email: email, password: password);
    return _auth.currentUser!.reauthenticateWithCredential(credential);
  }

  Future<void> changePassword(String newPassword) =>
      _auth.currentUser!.updatePassword(newPassword);
}
