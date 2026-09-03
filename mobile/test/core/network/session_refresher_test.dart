import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/network/session_refresher.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';

class _FakeStore implements TokenStore {
  final values = <String, String>{};

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// JWT expirant à [expiresAt]. La signature n'est jamais vérifiée côté
/// client, seul le claim `exp` compte ici.
String _jwt(DateTime expiresAt) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({
    'sub': 'u1',
    'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
  })));
  return 'eyJhbGciOiJIUzI1NiJ9.$payload.sig';
}

void main() {
  late _FakeStore store;
  late HttpServer server;
  var refreshCalls = 0;
  var refreshStatus = HttpStatus.ok;

  setUp(() async {
    store = _FakeStore();
    refreshCalls = 0;
    refreshStatus = HttpStatus.ok;
    // Un vrai POST /auth/refresh sur un serveur local, réponse enveloppée
    // comme celle de l'API.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      refreshCalls++;
      // Laisse le temps à un second appel concurrent de se présenter avant
      // que le premier ne reçoive sa réponse.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      request.response
        ..statusCode = refreshStatus
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'data': {
            'access_token': 'new-access-$refreshCalls',
            'refresh_token': 'new-refresh',
          },
        }));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  SessionRefresher refresher() => SessionRefresher(
      'http://127.0.0.1:${server.port}', SecureStorageService(store: store));

  test('lit la date d\'expiration d\'un JWT', () {
    final expiresAt = DateTime.utc(2026, 9, 3, 12, 0);
    expect(SessionRefresher.jwtExpiry(_jwt(expiresAt)), expiresAt);
    expect(SessionRefresher.jwtExpiry('pas-un-jwt'), isNull);
    expect(SessionRefresher.jwtExpiry('a.b.c'), isNull);
  });

  test('rend le token stocké tel quel tant qu\'il est loin d\'expirer',
      () async {
    final token = _jwt(DateTime.now().add(const Duration(minutes: 10)));
    store.values['access_token'] = token;
    store.values['refresh_token'] = 'refresh';

    expect(await refresher().validAccessToken(), token);
    expect(refreshCalls, 0);
  });

  test('renouvelle un token expiré avant de le rendre', () async {
    store.values['access_token'] =
        _jwt(DateTime.now().subtract(const Duration(minutes: 1)));
    store.values['refresh_token'] = 'refresh';

    expect(await refresher().validAccessToken(), 'new-access-1');
    expect(refreshCalls, 1);
    expect(store.values['access_token'], 'new-access-1');
    expect(store.values['refresh_token'], 'new-refresh');
  });

  test('renouvelle aussi un token sur le point d\'expirer', () async {
    store.values['access_token'] =
        _jwt(DateTime.now().add(const Duration(seconds: 5)));
    store.values['refresh_token'] = 'refresh';

    expect(await refresher().validAccessToken(), 'new-access-1');
  });

  test('sans session, rend null sans appel réseau', () async {
    expect(await refresher().validAccessToken(), isNull);
    expect(await refresher().refresh(), isNull);
    expect(refreshCalls, 0);
  });

  test('un renouvellement refusé efface les jetons', () async {
    refreshStatus = HttpStatus.unauthorized;
    store.values['access_token'] = 'stale';
    store.values['refresh_token'] = 'expired-refresh';

    expect(await refresher().refresh(), isNull);
    expect(store.values, isEmpty);
  });

  test('deux renouvellements concurrents ne font qu\'un appel', () async {
    store.values['refresh_token'] = 'refresh';
    final r = refresher();

    final tokens = await Future.wait([r.refresh(), r.refresh()]);

    expect(tokens, ['new-access-1', 'new-access-1']);
    expect(refreshCalls, 1);
    // Une fois terminé, un nouveau renouvellement repart bien de zéro.
    expect(await r.refresh(), 'new-access-2');
  });
}
