import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';

/// Records write concurrency and order so the sequential-write guarantee is
/// actually testable.
class _FakeStore implements TokenStore {
  final values = <String, String>{};
  final writeOrder = <String>[];
  int _inFlightWrites = 0;
  int maxConcurrentWrites = 0;
  bool unreadable = false;

  @override
  Future<void> write(String key, String value) async {
    _inFlightWrites++;
    if (_inFlightWrites > maxConcurrentWrites) {
      maxConcurrentWrites = _inFlightWrites;
    }
    await Future<void>.delayed(Duration.zero);
    values[key] = value;
    writeOrder.add(key);
    _inFlightWrites--;
  }

  @override
  Future<String?> read(String key) async {
    if (unreadable) return null;
    return values[key];
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('saves and reads back both tokens', () async {
    final store = _FakeStore();
    final service = SecureStorageService(store: store);

    await service.saveTokens(accessToken: 'access', refreshToken: 'refresh');

    expect(await service.getAccessToken(), 'access');
    expect(await service.getRefreshToken(), 'refresh');
  });

  test('writes tokens sequentially, never concurrently', () async {
    final store = _FakeStore();
    final service = SecureStorageService(store: store);

    await service.saveTokens(accessToken: 'access', refreshToken: 'refresh');

    // Concurrent first writes are what corrupt stores that lazily create an
    // encryption key on the first write.
    expect(store.maxConcurrentWrites, 1);
    expect(store.writeOrder, ['access_token', 'refresh_token']);
  });

  test('clearTokens removes both', () async {
    final store = _FakeStore();
    final service = SecureStorageService(store: store);

    await service.saveTokens(accessToken: 'access', refreshToken: 'refresh');
    await service.clearTokens();

    expect(await service.getAccessToken(), isNull);
    expect(await service.getRefreshToken(), isNull);
  });

  test('an unreadable store reads as signed out rather than throwing', () async {
    final store = _FakeStore();
    final service = SecureStorageService(store: store);
    await service.saveTokens(accessToken: 'access', refreshToken: 'refresh');
    store.unreadable = true;

    expect(await service.getAccessToken(), isNull);
  });
}
