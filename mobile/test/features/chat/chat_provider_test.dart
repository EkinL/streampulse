import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/chat/domain/chat_message.dart';
import 'package:streampulse/features/chat/presentation/providers/chat_provider.dart';
import 'package:web_socket_channel/io.dart';

Future<void> _waitUntil(bool Function() cond) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timeout en attendant la condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<String?> _token() async => 'tok';

/// Délai de reconnexion court : les tests ne dorment pas 2 s.
const _retry = Duration(milliseconds: 50);

void main() {
  test('construit une URL ws avec le token en parametre', () {
    final uri = ChatNotifier.chatUri('http://localhost:8080', 's1', 'tok');
    expect(uri.scheme, 'ws');
    expect(uri.path, '/streams/s1/chat/ws');
    expect(uri.queryParameters['token'], 'tok');

    final secure = ChatNotifier.chatUri('https://api.example.com', 's1', 'tok');
    expect(secure.scheme, 'wss');
  });

  test('se connecte, recoit les trames et envoie le texte', () async {
    // Un vrai serveur WebSocket local : le notifier est teste de bout en
    // bout, jusqu'au protocole (JSON dans les deux sens).
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final received = <String>[];
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      ws.add(jsonEncode({
        'type': 'user_joined',
        'id': 'p1',
        'stream_id': 's1',
        'user_id': 'u1',
        'username': 'alice',
        'sent_at': '2026-09-02T10:00:00Z',
      }));
      ws.listen((data) {
        received.add(data as String);
        ws.add(jsonEncode({
          'type': 'message',
          'id': 'm1',
          'stream_id': 's1',
          'user_id': 'u1',
          'username': 'alice',
          'text': 'salut',
          'sent_at': '2026-09-02T10:00:01Z',
        }));
      });
    });

    Uri? dialedUri;
    final notifier = ChatNotifier(
      's1',
      _token,
      channelFactory: (uri) {
        dialedUri = uri;
        return IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}');
      },
    );
    addTearDown(notifier.dispose);

    await _waitUntil(() => notifier.state.isConnected);
    expect(dialedUri?.path, '/streams/s1/chat/ws');
    expect(dialedUri?.queryParameters['token'], 'tok');

    await _waitUntil(() => notifier.state.messages.isNotEmpty);
    expect(notifier.state.messages.first.type, ChatMessage.typeUserJoined);

    notifier.send('  hello  ');
    await _waitUntil(() => notifier.state.messages.length == 2);
    expect(received, [jsonEncode({'text': 'hello'})]);
    expect(notifier.state.messages.last.text, 'salut');
  });

  test('sans token, ne tente pas de connexion', () async {
    final notifier = ChatNotifier(
      's1',
      () async => null,
      channelFactory: (uri) => fail('ne doit pas ouvrir de canal sans token'),
    );
    addTearDown(notifier.dispose);

    await _waitUntil(() => !notifier.state.isConnecting);
    expect(notifier.state.isConnected, isFalse);
    expect(notifier.state.statusText, 'Connectez-vous pour discuter');
  });

  test('signale la fin du live sur un 1001, sans se reconnecter', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      await ws.close(1001, 'stream ended');
    });

    var dials = 0;
    final notifier = ChatNotifier(
      's1',
      _token,
      channelFactory: (_) {
        dials++;
        return IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}');
      },
      reconnectDelay: _retry,
    );
    addTearDown(notifier.dispose);

    await _waitUntil(
        () => !notifier.state.isConnected && !notifier.state.isConnecting);
    await _waitUntil(() => notifier.state.statusText == 'Le live est terminé');

    // Le salon est fermé pour de bon : aucune nouvelle tentative.
    await Future<void>.delayed(_retry * 4);
    expect(dials, 1);
  });

  test('se reconnecte apres une coupure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    // Le serveur coupe la premiere connexion sans raison (pas un 1001) et
    // garde la seconde ouverte.
    var connections = 0;
    server.listen((request) async {
      final ws = await WebSocketTransformer.upgrade(request);
      connections++;
      if (connections == 1) await ws.close();
    });

    final notifier = ChatNotifier(
      's1',
      _token,
      channelFactory: (_) =>
          IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}'),
      reconnectDelay: _retry,
    );
    addTearDown(notifier.dispose);
    final statuses = <String>[];
    notifier.addListener((s) => statuses.add(s.statusText));

    await _waitUntil(() => connections == 2 && notifier.state.isConnected);
    expect(statuses, contains('Chat fermé'));
  });

  test('poignee de main refusee : indisponible, puis nouvel essai', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    // Premiere tentative refusee comme le ferait l'API sur un token expire
    // (pas d'upgrade), la seconde acceptee.
    var requests = 0;
    server.listen((request) async {
      requests++;
      if (requests == 1) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      await WebSocketTransformer.upgrade(request);
    });

    final notifier = ChatNotifier(
      's1',
      _token,
      channelFactory: (_) =>
          IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}'),
      reconnectDelay: _retry,
    );
    addTearDown(notifier.dispose);
    final statuses = <String>[];
    notifier.addListener((s) => statuses.add(s.statusText));

    await _waitUntil(() => notifier.state.isConnected);
    expect(requests, 2);
    expect(statuses, contains('Chat indisponible'));
  });
}
