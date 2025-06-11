// lib/services/hashing_service.dart
import 'package:bcrypt/bcrypt.dart';

class HashingService {
  // The 'cost' or 'work factor' for bcrypt. Higher is more secure but slower.
  // 10-12 is a common range. For mobile, consider performance.
  static const int _logRounds = 10;

  /// Hashes a plain text PIN using bcrypt.
  Future<String> hashPin(String plainPin) async {
    // BCrypt.hashpw automatically generates a salt.
    return BCrypt.hashpw(plainPin, BCrypt.gensalt(logRounds: _logRounds));
  }

  /// Verifies a plain text PIN against a stored hashed PIN.
  Future<bool> verifyPin(String plainPin, String hashedPin) async {
    // BCrypt.checkpw handles comparing the plain text against the hash.
    return BCrypt.checkpw(plainPin, hashedPin);
  }
}
