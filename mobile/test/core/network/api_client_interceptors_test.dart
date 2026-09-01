import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/network/api_client.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';

/// Fakes juste assez de `dart:io` HttpClient pour que
/// [IOHttpClientAdapter] (l'adaptateur par defaut de Dio) puisse fonctionner
/// sans toucher au reseau. Tout membre non implemente tombe sur
/// [noSuchMethod] : on ne fournit que ce que l'adaptateur utilise reellement
/// (voir dio/lib/src/adapters/io_adapter.dart).

class _FakeHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    values.forEach((k, v) => action(k, [v]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _Responder = Future<_FakeResponse> Function(_FakeRequest request, List<int> body);

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.method, this.uri, this._responder);

  @override
  final String method;
  @override
  final Uri uri;
  final _Responder _responder;
  final _FakeHeaders _headers = _FakeHeaders();
  final BytesBuilder _bodyBuilder = BytesBuilder();

  @override
  HttpHeaders get headers => _headers;

  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _bodyBuilder.add(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() => _responder(this, _bodyBuilder.takeBytes());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, List<int> body)
      : _body = Stream.value(Uint8List.fromList(body)) {
    _headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  }

  @override
  final int statusCode;
  @override
  final String reasonPhrase = '';
  final Stream<List<int>> _body;
  final _FakeHeaders _headers = _FakeHeaders();

  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  HttpHeaders get headers => _headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _body.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._responder);
  final _Responder _responder;
  final List<_FakeRequest> requests = [];

  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 3);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final req = _FakeRequest(method, url, _responder);
    requests.add(req);
    return req;
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Execute [body] dans une zone ou toute creation de `HttpClient` (dart:io)
/// est routee vers [responder] — y compris le `Dio()` prive que l'intercepteur
/// de refresh cree en interne, hors de portee d'un simple
/// `dio.httpClientAdapter = ...`.
Future<T> _withFakeHttp<T>(_Responder responder, Future<T> Function() body) {
  return HttpOverrides.runZoned(
    body,
    createHttpClient: (context) => _FakeHttpClient(responder),
  );
}

_FakeResponse _json(int statusCode, Object data) =>
    _FakeResponse(statusCode, utf8.encode(jsonEncode(data)));

class _FakeStore implements TokenStore {
  final values = <String, String>{};

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  late _FakeStore store;
  late ProviderContainer container;

  setUp(() {
    store = _FakeStore();
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(SecureStorageService(store: store)),
    ]);
  });

  tearDown(() => container.dispose());

  test('attache le bearer token quand un access token est stocke', () async {
    store.values['access_token'] = 'tok-123';
    _FakeHeaders? capturedHeaders;

    await _withFakeHttp((req, body) async {
      capturedHeaders = req.headers as _FakeHeaders;
      return _json(200, {'data': 'ok'});
    }, () async {
      final dio = container.read(dioProvider);
      await dio.get('/ping');
    });

    expect(capturedHeaders!.values['authorization'], 'Bearer tok-123');
  });

  test('n\'attache aucun bearer token sans access token stocke', () async {
    _FakeHeaders? capturedHeaders;

    await _withFakeHttp((req, body) async {
      capturedHeaders = req.headers as _FakeHeaders;
      return _json(200, {'data': 'ok'});
    }, () async {
      final dio = container.read(dioProvider);
      await dio.get('/ping');
    });

    expect(capturedHeaders!.values.containsKey('authorization'), isFalse);
  });

  test('pose toujours un traceparent au format W3C', () async {
    _FakeHeaders? capturedHeaders;

    await _withFakeHttp((req, body) async {
      capturedHeaders = req.headers as _FakeHeaders;
      return _json(200, {'data': 'ok'});
    }, () async {
      final dio = container.read(dioProvider);
      await dio.get('/ping');
    });

    expect(
      capturedHeaders!.values['traceparent'],
      matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-01$')),
    );
  });

  test('sur 401 avec refresh token valide : rafraichit, sauvegarde et rejoue la requete', () async {
    store.values['refresh_token'] = 'old-refresh';
    var attempt = 0;
    String? retryAuthHeader;

    await _withFakeHttp((req, body) async {
      if (req.uri.path == '/auth/refresh') {
        return _json(200, {
          'data': {'access_token': 'new-access', 'refresh_token': 'new-refresh'},
        });
      }
      attempt++;
      if (attempt == 1) {
        return _json(401, {'error': 'unauthorized'});
      }
      retryAuthHeader = (req.headers as _FakeHeaders).values['authorization'];
      return _json(200, {'data': 'ok'});
    }, () async {
      final dio = container.read(dioProvider);
      final response = await dio.get('/protected');
      expect(response.data, {'data': 'ok'});
    });

    expect(retryAuthHeader, 'Bearer new-access');
    expect(store.values['access_token'], 'new-access');
    expect(store.values['refresh_token'], 'new-refresh');
  });

  test('sur 401 avec refresh token rejete : efface les jetons et rejette en UnauthorizedException',
      () async {
    store.values['access_token'] = 'stale-access';
    store.values['refresh_token'] = 'expired-refresh';

    await _withFakeHttp((req, body) async {
      if (req.uri.path == '/auth/refresh') {
        return _json(401, {'error': 'invalid refresh token'});
      }
      return _json(401, {'error': 'unauthorized'});
    }, () async {
      final dio = container.read(dioProvider);
      await expectLater(
        dio.get('/protected'),
        throwsA(isA<DioException>().having((e) => e.error, 'error', isA<UnauthorizedException>())),
      );
    });

    expect(store.values.containsKey('access_token'), isFalse);
    expect(store.values.containsKey('refresh_token'), isFalse);
  });

  test('sur 401 sans refresh token stocke : laisse passer l\'erreur telle quelle', () async {
    await _withFakeHttp((req, body) async {
      return _json(401, {'error': 'unauthorized'});
    }, () async {
      final dio = container.read(dioProvider);
      await expectLater(
        dio.get('/protected'),
        throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          401,
        )),
      );
    });

    expect(store.values.containsKey('access_token'), isFalse);
  });

  test('une erreur non-401 n\'est pas interceptee', () async {
    await _withFakeHttp((req, body) async {
      return _json(500, {'error': 'boom'});
    }, () async {
      final dio = container.read(dioProvider);
      await expectLater(
        dio.get('/protected'),
        throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          500,
        )),
      );
    });
  });
}
