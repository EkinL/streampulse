// Tests de BroadcastNotifier : la capture micro est simulee (mock du
// plugin record), le backend par un HttpServer local qui recoit le POST
// chunke. Verifie que les octets du micro arrivent bien au serveur, que
// l'arret libere tout, et qu'une coupure de connexion est rattrapee.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import 'package:streampulse/app/constants.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/streams/presentation/providers/broadcast_provider.dart';

class _MockRecorder extends Mock implements AudioRecorder {}

class _MemoryStore implements TokenStore {
  final Map<String, String> _values;
  _MemoryStore(this._values);
  @override
  Future<void> write(String key, String value) async => _values[key] = value;
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Un chunk micro realiste : 4096 octets (2048 echantillons PCM16). Le
/// client HTTP de dart:io tamponne l'envoi par blocs de 8 Ko, un chunk
/// minuscule ne partirait jamais.
Uint8List _chunk(int fill) => Uint8List(4096)..fillRange(0, 4096, fill);

/// Backend minimal : accumule les corps des POST /streams/:id/broadcast.
class _FakeBackend {
  late final HttpServer _server;
  final List<HttpRequest> requests = [];
  final List<String> authHeaders = [];
  final received = BytesBuilder();
  final _firstChunk = <Completer<void>>[];

  /// Si vrai, le serveur detruit la connexion apres le premier chunk recu
  /// (simule un backend qui redemarre).
  bool closeAfterFirstChunk = false;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      requests.add(req);
      authHeaders.add(req.headers.value('authorization') ?? '');
      var first = true;
      try {
        await for (final chunk in req) {
          received.add(chunk);
          if (first) {
            first = false;
            for (final c in _firstChunk) {
              if (!c.isCompleted) c.complete();
            }
            if (closeAfterFirstChunk) {
              (await req.response.detachSocket(writeHeaders: false)).destroy();
              return;
            }
          }
        }
        await req.response.close();
      } catch (_) {
        // Connexion coupee (arret du client ou close(force) du serveur).
      }
    });
  }

  Future<void> waitForChunk() {
    final c = Completer<void>();
    _firstChunk.add(c);
    return c.future.timeout(const Duration(seconds: 5));
  }

  Future<void> close() => _server.close(force: true);
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
      SecureStorageService(
        store: _MemoryStore({AppConstants.accessTokenKey: 'tok'}),
      ),
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

    final chunk = backend.waitForChunk();
    mic.add(_chunk(1));
    mic.add(_chunk(2));
    await chunk;

    expect(backend.requests.single.uri.path, '/streams/s1/broadcast');
    expect(backend.authHeaders.single, 'Bearer tok');
    final bytes = backend.received.toBytes();
    expect(bytes.length, greaterThanOrEqualTo(4096));
    expect(bytes.first, 1);

    // Redemander le meme flux ne relance pas la capture.
    expect(await notifier.start('s1'), isTrue);
    verify(() => recorder.startStream(any())).called(1);

    await notifier.stop();
    expect(notifier.state.isBroadcasting, isFalse);
    expect(notifier.state.dropCount, 0);
    verify(() => recorder.stop()).called(1);
  });

  test('connexion coupee par le serveur : comptee et rouverte', () async {
    backend.closeAfterFirstChunk = true;
    await notifier.start('s1');

    final first = backend.waitForChunk();
    mic.add(_chunk(9));
    mic.add(_chunk(9));
    await first;

    // Connexion detruite cote serveur : l'ecriture suivante du micro echoue,
    // le notifier compte la coupure puis rouvre.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (notifier.state.dropCount == 0 && DateTime.now().isBefore(deadline)) {
      mic.add(_chunk(9));
      mic.add(_chunk(9));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(notifier.state.dropCount, 1);
    expect(notifier.state.isBroadcastingStream('s1'), isTrue);

    backend.closeAfterFirstChunk = false;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final second = backend.waitForChunk();
    mic.add(_chunk(7));
    mic.add(_chunk(7));
    await second;

    expect(backend.requests.length, 2);
    final bytes = backend.received.toBytes();
    expect(bytes.first, 9);
    expect(bytes.last, 7);

    await notifier.stop();
  });
}
