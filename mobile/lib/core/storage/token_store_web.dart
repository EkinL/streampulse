import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'token_store.dart';

TokenStore createTokenStore() => WebTokenStore();

/// Browser `localStorage`, via shared_preferences.
///
/// Tokens are visible to anything running on the origin either way; the JWTs
/// are short-lived and the refresh token is revocable server-side.
class WebTokenStore implements TokenStore {
  static const _prefix = 'streampulse.';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<void> write(String key, String value) async {
    final prefs = await _prefs;
    await prefs.setString('$_prefix$key', value);
  }

  @override
  Future<String?> read(String key) async {
    try {
      final prefs = await _prefs;
      return prefs.getString('$_prefix$key');
    } catch (e) {
      debugPrint('Token store read failed for "$key": $e');
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await _prefs;
    await prefs.remove('$_prefix$key');
  }
}
