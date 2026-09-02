import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/app/theme.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';
import 'package:streampulse/features/chat/domain/chat_message.dart';
import 'package:streampulse/features/chat/presentation/providers/chat_provider.dart';
import 'package:streampulse/features/chat/presentation/widgets/stream_chat_panel.dart';

class _NullStore implements TokenStore {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthLocalSource extends Mock implements AuthLocalSource {}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(AuthState initial)
      : super(_MockAuthRepository(), _MockAuthLocalSource()) {
    state = initial;
  }
}

/// Notifier de chat sans connexion réseau : l'état est posé par le test.
class _StubChatNotifier extends ChatNotifier {
  final sent = <String>[];

  _StubChatNotifier(String streamId)
      : super(streamId, SecureStorageService(store: _NullStore()),
            connectOnInit: false);

  void setTestState(ChatState newState) => state = newState;

  @override
  void send(String text) => sent.add(text.trim());
}

ChatMessage _message(String username, String text, {String userId = 'u1'}) =>
    ChatMessage(
      type: ChatMessage.typeMessage,
      id: 'id-$text',
      streamId: 's1',
      userId: userId,
      username: username,
      text: text,
      sentAt: DateTime.utc(2026, 9, 2, 10),
    );

Future<_StubChatNotifier> _pump(
  WidgetTester tester, {
  AuthState auth = const AuthLoading(),
}) async {
  final notifier = _StubChatNotifier('s1');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatProvider.overrideWith((ref, streamId) => notifier),
        authProvider.overrideWith((ref) => _FakeAuthNotifier(auth)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: StreamChatPanel(streamId: 's1')),
      ),
    ),
  );
  await tester.pump();
  return notifier;
}

void main() {
  testWidgets('affiche les messages et les lignes de présence',
      (tester) async {
    final notifier = await _pump(tester);
    notifier.setTestState(ChatState(
      isConnected: true,
      messages: [
        ChatMessage(
          type: ChatMessage.typeUserJoined,
          id: 'p1',
          streamId: 's1',
          userId: 'u2',
          username: 'bob',
          text: '',
          sentAt: DateTime.utc(2026, 9, 2, 10),
        ),
        _message('alice', 'salut tout le monde'),
      ],
    ));
    await tester.pump();

    expect(find.text('Chat du live'), findsOneWidget);
    expect(find.text('bob a rejoint le chat'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('salut tout le monde'), findsOneWidget);
  });

  testWidgets('mes messages sont signés « Vous »', (tester) async {
    const me = UserModel(
        id: 'u1', email: 'a@a.fr', username: 'alice', role: 'user');
    final notifier = await _pump(tester,
        auth: const AuthAuthenticated(user: me, token: 't'));
    notifier.setTestState(ChatState(
      isConnected: true,
      messages: [
        _message('alice', 'mon message', userId: 'u1'),
        _message('bob', 'sa réponse', userId: 'u2'),
      ],
    ));
    await tester.pump();

    expect(find.text('Vous'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets('envoie le message saisi puis vide le champ', (tester) async {
    final notifier = await _pump(tester);
    notifier.setTestState(const ChatState(isConnected: true));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byTooltip('Envoyer le message'));
    await tester.pump();

    expect(notifier.sent, ['hello']);
    expect(find.text('hello'), findsNothing);
  });

  testWidgets('champ désactivé tant que le chat n\'est pas connecté',
      (tester) async {
    final notifier = await _pump(tester);
    notifier.setTestState(
        const ChatState(statusText: 'Chat indisponible'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });
}
