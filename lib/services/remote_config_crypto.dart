import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';

/// AES-256-GCM decode of the remote-config blob (Feature 5c).
///
/// HONESTY NOTE: because the decryption key ships inside the APK, this is
/// OBFUSCATION, not real security. Anyone who decompiles the app can extract
/// the key and read or forge the config. The format is documented in
/// tools/remote_config/README.md. Never build anything security-critical
/// (license checks, payments) on top of it.
///
/// Wire format (matches Python `cryptography` AESGCM and the `encrypt`
/// package's GCM, both of which append the 16-byte tag to the ciphertext):
///   base64( nonce(12) || ciphertext || gcmTag(16) )   — single line.
class RemoteConfigCrypto {
  const RemoteConfigCrypto._();

  static const int _nonceLen = 12;
  static const int _tagLen = 16;

  /// Decrypt and return the UTF-8 plaintext. Throws on a short blob or on GCM
  /// authentication failure (tampered/corrupted blob) — callers treat any
  /// throw as a fetch failure and fall back to cache/defaults.
  static String decrypt(String blobBase64, Uint8List key) {
    _requireKey(key);
    final raw = base64.decode(base64.normalize(blobBase64.trim()));
    if (raw.length < _nonceLen + _tagLen) {
      throw const FormatException('Remote config blob is too short.');
    }
    final nonce = Uint8List.sublistView(raw, 0, _nonceLen);
    final cipherAndTag = Uint8List.sublistView(raw, _nonceLen);
    final encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));
    final plain =
        encrypter.decryptBytes(Encrypted(cipherAndTag), iv: IV(nonce));
    return utf8.decode(plain);
  }

  /// Encrypt UTF-8 [plaintext]; used by tests for round-trips (the real
  /// encryption is done by the Python dev script).
  static String encrypt(String plaintext, Uint8List key, {Uint8List? nonce}) {
    _requireKey(key);
    final iv = nonce != null ? IV(nonce) : IV.fromSecureRandom(_nonceLen);
    final encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));
    final enc = encrypter.encryptBytes(utf8.encode(plaintext), iv: iv);
    return base64.encode(Uint8List.fromList([...iv.bytes, ...enc.bytes]));
  }

  /// Reassemble the 32-byte key from XOR parts held separately in the binary
  /// (raises the decompilation bar slightly; see honesty note). All parts must
  /// be 32 bytes.
  static Uint8List combineKeyParts(List<List<int>> parts) {
    if (parts.isEmpty) throw ArgumentError('No key parts.');
    final out = Uint8List(32);
    for (final part in parts) {
      if (part.length != 32) {
        throw ArgumentError('Each key part must be 32 bytes.');
      }
      for (var i = 0; i < 32; i++) {
        out[i] ^= part[i];
      }
    }
    return out;
  }

  static void _requireKey(Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError('AES-256 key must be 32 bytes, got ${key.length}.');
    }
  }
}
