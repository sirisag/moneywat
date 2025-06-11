// lib/services/encryption_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart' as crypto; // For SHA256 to derive key

class EncryptionService {
  // Method to derive a fixed-length key from treasurer IDs
  enc.Key _deriveKey(String treasurerPrimaryId, String treasurerSecondaryId) {
    final combinedId = treasurerPrimaryId + treasurerSecondaryId;
    // Use SHA-256 hash of combined ID to create a 32-byte key suitable for AES-256
    final keyBytes = crypto.sha256.convert(utf8.encode(combinedId)).bytes;
    return enc.Key(Uint8List.fromList(keyBytes));
  }

  // Generates a random 16-byte IV for AES CBC mode
  enc.IV _generateIv() {
    return enc.IV.fromSecureRandom(16); // AES block size is 16 bytes
  }

  /// Encrypts a plain text string using AES-256 CBC mode.
  /// The IV is prepended to the ciphertext, base64 encoded.
  String encryptData(String plainText, String treasurerPrimaryId,
      String treasurerSecondaryId) {
    final key = _deriveKey(treasurerPrimaryId, treasurerSecondaryId);
    final iv = _generateIv();
    final encrypter =
        enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'));

    final encrypted = encrypter.encrypt(plainText, iv: iv);
    // Prepend IV to the ciphertext for use during decryption
    // Format: base64(iv):base64(ciphertext)
    return "${iv.base64}:${encrypted.base64}";
  }

  /// Decrypts an AES-256 CBC encrypted string.
  /// Expects the input format: base64(iv):base64(ciphertext)
  String? decryptData(String encryptedTextWithIv, String treasurerPrimaryId,
      String treasurerSecondaryId) {
    try {
      final parts = encryptedTextWithIv.split(':');
      if (parts.length != 2) {
        print("Decryption error: Invalid encrypted text format.");
        return null; // Invalid format
      }

      final iv = enc.IV.fromBase64(parts[0]);
      final encryptedData = enc.Encrypted.fromBase64(parts[1]);
      final key = _deriveKey(treasurerPrimaryId, treasurerSecondaryId);
      final encrypter =
          enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'));

      return encrypter.decrypt(encryptedData, iv: iv);
    } catch (e) {
      print('Decryption failed: $e');
      return null;
    }
  }
}
