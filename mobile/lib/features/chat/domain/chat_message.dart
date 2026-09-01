/// Une trame du chat de live, telle que le backend l'envoie sur le
/// WebSocket `/streams/{id}/chat/ws` (schéma `ChatMessage` de l'OpenAPI).
class ChatMessage {
  static const typeMessage = 'message';
  static const typeUserJoined = 'user_joined';
  static const typeUserLeft = 'user_left';

  final String type;
  final String id;
  final String streamId;
  final String userId;
  final String username;
  final String text;
  final DateTime sentAt;

  const ChatMessage({
    required this.type,
    required this.id,
    required this.streamId,
    required this.userId,
    required this.username,
    required this.text,
    required this.sentAt,
  });

  /// Événement de présence (arrivée/départ), affiché comme une ligne
  /// système et non comme une bulle de message.
  bool get isPresence => type != typeMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      type: json['type'] as String? ?? typeMessage,
      id: json['id'] as String? ?? '',
      streamId: json['stream_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      text: json['text'] as String? ?? '',
      sentAt: DateTime.tryParse(json['sent_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
