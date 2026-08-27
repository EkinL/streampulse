import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'token_store.dart';

TokenStore createTokenStore() => IoTokenStore();

/// Keychain (iOS) / EncryptedSharedPreferences (Android).
class IoTokenStore implements TokenStore {
  final FlutterSecureStorage _storage;

  IoTokenStore()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('Token store read failed for "$key": $e');
      return null;
    }
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
