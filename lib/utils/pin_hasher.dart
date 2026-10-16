import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class PinHasher {
  static String generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String hashPin(String rawPin, String salt) {
    final bytes = utf8.encode(rawPin + salt);
    return sha256.convert(bytes).toString();
  }

  static bool verifyPin(String rawPin, String storedHash, String salt) {
    return hashPin(rawPin, salt) == storedHash;
  }
}
