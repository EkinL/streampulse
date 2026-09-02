import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../app/constants.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../domain/chat_message.dart';

/// Fabrique de canal WebSocket, injectable pour les tests.
typedef ChatChannelFactory = WebSocketChannel Function(Uri uri);

class ChatState {
  final List<ChatMessage> messages;
  final bool isConnecting;
  final bool isConnected;
  final String statusText;

  const ChatState({
    this.messages = const [],
    this.isConnecting = false,
    this.isConnected = false,
    this.statusText = '',
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isConnecting,
    bool? isConnected,
    String? statusText,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isConnecting: isConnecting ?? this.isConnecting,
      isConnected: isConnected ?? this.isConnected,
      statusText: statusText ?? this.statusText,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  /// Garde-fou local : au-delà, les plus vieux messages sont oubliés.
  /// Le serveur ne rejoue de toute façon que les 50 derniers.
  static const int maxMessages = 200;

  final String streamId;
  final SecureStorageService _secureStorage;
  final ChatChannelFactory _channelFactory;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  ChatNotifier(
    this.streamId,
    this._secureStorage, {
    ChatChannelFactory? channelFactory,
    bool connectOnInit = true,
  })  : _channelFactory = channelFactory ?? WebSocketChannel.connect,
        super(const ChatState()) {
    if (connectOnInit) {
      connect();
    }
  }

  /// URL du salon : même hôte que l'API, schéma ws(s). Le token passe en
  /// paramètre de requête, seul canal d'auth commun à toutes les
  /// plateformes (un WebSocket navigateur ne peut pas poser de header).
  static Uri chatUri(String baseUrl, String streamId, String token) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${ApiEndpoints.stream(streamId)}/chat/ws',
      queryParameters: {'token': token},
    );
  }

  Future<void> connect() async {
    if (state.isConnecting || state.isConnected) return;
    state = state.copyWith(isConnecting: true, statusText: 'Connexion…');

    try {
      final token = await _secureStorage.getAccessToken();
      if (token == null) {
        state = state.copyWith(
            isConnecting: false, statusText: 'Connectez-vous pour discuter');
        return;
      }

      final channel =
          _channelFactory(chatUri(AppConstants.apiBaseUrl, streamId, token));
      await channel.ready;
      if (!mounted) {
        channel.sink.close();
        return;
      }
      _channel = channel;

      _sub = channel.stream.listen(
        _onFrame,
        onError: (Object error) {
          debugPrint('Chat error: $error');
          _onClosed('Chat indisponible');
        },
        onDone: () => _onClosed('Chat fermé'),
        cancelOnError: true,
      );

      state = state.copyWith(
          isConnecting: false, isConnected: true, statusText: '');
    } catch (e) {
      debugPrint('Chat connect failed: $e');
      if (mounted) {
        state = state.copyWith(
            isConnecting: false, statusText: 'Chat indisponible');
      }
    }
  }

  void _onFrame(dynamic frame) {
    if (!mounted) return;
    try {
      final decoded = jsonDecode(frame as String) as Map<String, dynamic>;
      final message = ChatMessage.fromJson(decoded);
      var messages = [...state.messages, message];
      if (messages.length > maxMessages) {
        messages = messages.sublist(messages.length - maxMessages);
      }
      state = state.copyWith(messages: messages);
    } catch (e) {
      debugPrint('Chat frame ignored: $e');
    }
  }

  void _onClosed(String reason) {
    if (!mounted) return;
    state = state.copyWith(
      isConnected: false,
      isConnecting: false,
      // 1001 = le diffuseur a arrêté le live, le salon est fermé.
      statusText:
          _channel?.closeCode == 1001 ? 'Le live est terminé' : reason,
    );
  }

  /// Envoie un message ; l'auteur et l'horodatage sont posés côté serveur.
  void send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !state.isConnected) return;
    _channel?.sink.add(jsonEncode({'text': trimmed}));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}

/// Un salon (et une connexion WebSocket) par flux, fermé automatiquement
/// quand plus personne n'affiche le chat (autoDispose).
final chatProvider = StateNotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, String>((ref, streamId) {
  return ChatNotifier(streamId, ref.read(secureStorageProvider));
});
