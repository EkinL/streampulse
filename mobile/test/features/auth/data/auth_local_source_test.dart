import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';

class _FakeStore implements TokenStore {
  final _values = <String, String>{};

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

void main() {
  late _FakeStore store;
  late AuthLocalSource source;

  setUp(() {
    store = _FakeStore();
    source = AuthLocalSource(SecureStorageService(store: store));
  });

  test('saveTokens puis getAccessToken/getRefreshToken relisent les valeurs', () async {
    await source.saveTokens(accessToken: 'access-1', refreshToken: 'refresh-1');

    expect(await source.getAccessToken(), 'access-1');
    expect(await source.getRefreshToken(), 'refresh-1');
  });

  test('clearTokens efface les deux jetons', () async {
    await source.saveTokens(accessToken: 'access-1', refreshToken: 'refresh-1');
    await source.clearTokens();

    expect(await source.getAccessToken(), isNull);
    expect(await source.getRefreshToken(), isNull);
  });

  group('hasValidToken', () {
    test('faux quand aucun jeton n\'est stocke', () async {
      expect(await source.hasValidToken(), isFalse);
    });

    test('faux quand le jeton stocke est vide', () async {
      await store.write('access_token', '');
      expect(await source.hasValidToken(), isFalse);
    });

    test('vrai quand un jeton non vide est stocke', () async {
      await source.saveTokens(accessToken: 'access-1', refreshToken: 'refresh-1');
      expect(await source.hasValidToken(), isTrue);
    });
  });
}
