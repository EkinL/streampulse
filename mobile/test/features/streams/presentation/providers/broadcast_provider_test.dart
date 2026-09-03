// Tests de BroadcastNotifier : la capture micro est simulee (mock du
// plugin record), le backend par un vrai serveur WebSocket local qui recoit
// les trames binaires. Verifie que les octets du micro arrivent bien au
// serveur avec le token, que l'arret libere tout, et qu'une coupure de
// connexion est comptee puis rattrapee.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import 'package:streampulse/features/streams/presentation/providers/broadcast_provider.dart';

class _MockRecorder extends Mock implements AudioRecorder {}

Future<String?> _token() async => 'tok';

/// Un chunk micro realiste : 4096 octets (2048 echantillons PCM16).
Uint8List _chunk(int fill) => Uint8List(4096)..fillRange(0, 4096, fill);

Future<void> _waitUntil(bool Function() cond, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) fail('timeout: $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Backend minimal : accepte les WebSocket sur /streams/:id/broadcast/ws et
/// accumule les trames recues.
class _FakeBackend {
  late final HttpServer _server;
  final List<Uri> requests = [];
  final received = BytesBuilder();
  final _sockets = <WebSocket>[];

  /// Si vrai, le serveur ferme la connexion apres la premiere trame recue
  /// (simule un backend qui redemarre).
  bool closeAfterFirstFrame = false;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      requests.add(req.uri);
      final ws = await WebSocketTransformer.upgrade(req);
      _sockets.add(ws);
      var first = true;
      ws.listen((frame) {
        received.add(frame as List<int>);
        if (first && closeAfterFirstFrame) {
          ws.close();
        }
        first = false;
      }, onError: (Object _) {});
    });
  }

  Future<void> close() async {
    for (final ws in _sockets) {
      await ws.close();
    }
    await _server.close(force: true);
  }
}

void main() {
  late _MockRecorder recorder;
  late StreamController<Uint8List> mic;
  late _FakeBackend backend;
  late BroadcastNotifier notifier;

  setUpAll(() {
    registerFallbackValue(const RecordConfig());
  });

  setUp(() async {
    recorder = _MockRecorder();
    mic = StreamController<Uint8List>();
    when(() => recorder.hasPermission()).thenAnswer((_) async => true);
    when(() => recorder.startStream(any())).thenAnswer((_) async => mic.stream);
    when(() => recorder.isRecording()).thenAnswer((_) async => true);
    when(() => recorder.stop()).thenAnswer((_) async => null);
    when(() => recorder.dispose()).thenAnswer((_) async {});

    backend = _FakeBackend();
    await backend.start();

    notifier = BroadcastNotifier(
      _token,
      recorder: recorder,
      baseUrl: backend.baseUrl,
      retryDelay: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    notifier.dispose();
    // Pas de await : sans auditeur, close() ne se resout jamais.
    unawaited(mic.close());
    await backend.close();
  });

  test('construit une URL ws avec le token en parametre', () {
    final uri = BroadcastNotifier.broadcastUri('http://localhost:8080', 's1', 'tok');
    expect(uri.scheme, 'ws');
    expect(uri.path, '/streams/s1/broadcast/ws');
    expect(uri.queryParameters['token'], 'tok');

    final secure = BroadcastNotifier.broadcastUri('https://api.example.com', 's1', 'tok');
    expect(secure.scheme, 'wss');
    expect(secure.host, 'api.example.com');

    // API servie sous un prefixe : conserve, comme le fait Dio.
    final prefixed = BroadcastNotifier.broadcastUri('https://example.com/api/', 's1', 'tok');
    expect(prefixed.path, '/api/streams/s1/broadcast/ws');
  });

  test('permission micro refusee : rien ne demarre', () async {
    when(() => recorder.hasPermission()).thenAnswer((_) async => false);

    expect(await notifier.start('s1'), isFalse);

    expect(notifier.state.isBroadcasting, isFalse);
    verifyNever(() => recorder.startStream(any()));
  });

  test('les octets du micro arrivent au backend, avec le token', () async {
    expect(await notifier.start('s1'), isTrue);
    expect(notifier.state.isBroadcastingStream('s1'), isTrue);
    expect(notifier.state.startedAt, isNotNull);
    expect(notifier.state.isConnected, isFalse);

    await _waitUntil(() => notifier.state.isConnected, 'connexion ouverte');
    mic.add(_chunk(1));
    mic.add(_chunk(2));
    await _waitUntil(() => backend.received.length >= 8192, 'trames recues');

    expect(backend.requests.single.path, '/streams/s1/broadcast/ws');
    expect(backend.requests.single.queryParameters['token'], 'tok');
    final bytes = backend.received.toBytes();
    expect(bytes.first, 1);
    expect(bytes.last, 2);

    // Redemander le meme flux ne relance pas la capture.
    expect(await notifier.start('s1'), isTrue);
    verify(() => recorder.startStream(any())).called(1);

    await notifier.stop();
    expect(notifier.state.isBroadcasting, isFalse);
    expect(notifier.state.isConnected, isFalse);
    expect(notifier.state.dropCount, 0);
    verify(() => recorder.stop()).called(1);
  });

  test('connexion fermee par le serveur : comptee et rouverte', () async {
    backend.closeAfterFirstFrame = true;
    await notifier.start('s1');
    await _waitUntil(() => notifier.state.isConnected, 'premiere connexion');

    mic.add(_chunk(9));
    // Le serveur ferme apres cette trame : le notifier compte la coupure,
    // n'est plus "connecte", puis rouvre.
    await _waitUntil(() => notifier.state.dropCount == 1, 'coupure comptee');
    expect(notifier.state.isBroadcastingStream('s1'), isTrue);

    backend.closeAfterFirstFrame = false;
    await _waitUntil(() => notifier.state.isConnected, 'reconnexion');
    mic.add(_chunk(7));
    await _waitUntil(() => backend.received.length >= 8192, 'trame apres reconnexion');

    expect(backend.requests.length, 2);
    final bytes = backend.received.toBytes();
    expect(bytes.first, 9);
    expect(bytes.last, 7);

    await notifier.stop();
  });

  test('arret pendant la reconnexion : plus aucune tentative', () async {
    backend.closeAfterFirstFrame = true;
    await notifier.start('s1');
    await _waitUntil(() => notifier.state.isConnected, 'premiere connexion');
    mic.add(_chunk(3));
    await _waitUntil(() => notifier.state.dropCount == 1, 'coupure comptee');

    await notifier.stop();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(notifier.state.isBroadcasting, isFalse);
    expect(backend.requests.length, 1);
  });
}
