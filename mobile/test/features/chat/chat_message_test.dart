import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/chat/domain/chat_message.dart';

void main() {
  test('parse une trame message du backend', () {
    final message = ChatMessage.fromJson({
      'type': 'message',
      'id': 'm1',
      'stream_id': 's1',
      'user_id': 'u1',
      'username': 'alice',
      'text': 'salut',
      'sent_at': '2026-09-02T10:00:00Z',
    });

    expect(message.type, ChatMessage.typeMessage);
    expect(message.isPresence, isFalse);
    expect(message.username, 'alice');
    expect(message.text, 'salut');
    expect(message.sentAt, DateTime.utc(2026, 9, 2, 10));
  });

  test('parse un evenement de presence sans texte', () {
    final message = ChatMessage.fromJson({
      'type': 'user_joined',
      'id': 'm2',
      'stream_id': 's1',
      'user_id': 'u2',
      'username': 'bob',
      'sent_at': '2026-09-02T10:00:00Z',
    });

    expect(message.type, ChatMessage.typeUserJoined);
    expect(message.isPresence, isTrue);
    expect(message.text, isEmpty);
  });

  test('tolere les champs manquants plutot que de jeter', () {
    final message = ChatMessage.fromJson(const {});

    expect(message.type, ChatMessage.typeMessage);
    expect(message.username, isEmpty);
  });
}
