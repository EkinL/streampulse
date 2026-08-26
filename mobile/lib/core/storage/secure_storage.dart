import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'token_store.dart';
import 'token_store_io.dart'
    if (dart.library.js_interop) 'token_store_web.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// Stores the auth tokens on whichever backing store the platform provides.
class SecureStorageService {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  final TokenStore _store;

  SecureStorageService({TokenStore? store})
      : _store = store ?? createTokenStore();

  /// Written one after the other, never concurrently: some backing stores
  /// initialise lazily on first write and do not tolerate a race.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _store.write(_accessTokenKey, accessToken);
    await _store.write(_refreshTokenKey, refreshToken);
  }

  Future<String?> getAccessToken() => _store.read(_accessTokenKey);

  Future<String?> getRefreshToken() => _store.read(_refreshTokenKey);

  Future<void> clearTokens() async {
    await _store.delete(_accessTokenKey);
    await _store.delete(_refreshTokenKey);
  }
}
