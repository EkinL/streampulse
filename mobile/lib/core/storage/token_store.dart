/// Platform-specific persistence for the auth tokens.
///
/// Mobile gets the OS keychain/keystore via `flutter_secure_storage`. The web
/// console gets `localStorage` through `shared_preferences`: a browser has no
/// keychain, and `flutter_secure_storage_web` only keeps its AES key in
/// `localStorage` next to the ciphertext, so it adds no real protection while
/// adding a failure mode (concurrent first writes race to generate the key and
/// leave undecryptable values behind).
abstract class TokenStore {
  Future<void> write(String key, String value);

  /// Returns null rather than throwing when a value cannot be read, so a
  /// corrupted store signs the user out instead of breaking every request.
  Future<String?> read(String key);

  Future<void> delete(String key);
}
