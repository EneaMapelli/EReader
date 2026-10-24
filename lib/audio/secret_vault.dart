import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secrets must never appear in SQLite, book metadata, logs, URL query,
/// test fixtures containing real keys, or exported settings.
abstract interface class SpeechSecretVault {
  Future<String?> readKey(String providerId);
  Future<void> saveKey(String providerId, String value);
  Future<void> deleteKey(String providerId);
}

class PlatformSpeechSecretVault implements SpeechSecretVault {
  PlatformSpeechSecretVault({FlutterSecureStorage? secureStorage})
      : _storage = secureStorage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  static String _vaultKey(String providerId) {
    if (!RegExp(r'^[a-z0-9-]{2,64}$').hasMatch(providerId)) {
      throw const FormatException('Invalid provider ID');
    }
    return 'ereader.tts.key.v1.' + providerId;
  }

  @override
  Future<String?> readKey(String providerId) =>
      _storage.read(key: _vaultKey(providerId));

  @override
  Future<void> saveKey(String providerId, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 4096) {
      throw const FormatException('Credential is missing or excessively long');
    }
    await _storage.write(key: _vaultKey(providerId), value: trimmed);
  }

  @override
  Future<void> deleteKey(String providerId) =>
      _storage.delete(key: _vaultKey(providerId));
}
