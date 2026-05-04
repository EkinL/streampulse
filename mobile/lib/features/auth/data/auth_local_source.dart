import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/secure_storage.dart';

final authLocalSourceProvider = Provider<AuthLocalSource>((ref) {
  return AuthLocalSource(ref.read(secureStorageProvider));
});

class AuthLocalSource {
  final SecureStorageService _secureStorage;

  AuthLocalSource(this._secureStorage);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secureStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<String?> getAccessToken() async {
    return _secureStorage.getAccessToken();
  }

  Future<String?> getRefreshToken() async {
    return _secureStorage.getRefreshToken();
  }

  Future<void> clearTokens() async {
    await _secureStorage.clearTokens();
  }

  Future<bool> hasValidToken() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
