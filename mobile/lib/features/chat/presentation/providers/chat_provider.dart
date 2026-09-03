import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../app/constants.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/session_refresher.dart';
import '../../domain/chat_message.dart';

/// Fabrique de canal WebSocket, injectable pour les tests.
typedef ChatChannelFactory = WebSocketChannel Function(Uri uri);

/// Fournit un access token valide pour la poignée de main, null sans session.
typedef ChatTokenProvider = Future<String?> Function();

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

  /// Délai avant de retenter après une coupure, doublé à chaque nouvel échec
  /// jusqu'à [maxReconnectDelay] pour ne pas marteler un serveur en panne.
  static const Duration initialReconnectDelay = Duration(seconds: 2);
  static const Duration maxReconnectDelay = Duration(seconds: 30);

  final String streamId;
  final ChatTokenProvider _accessToken;
  final ChatChannelFactory _channelFactory;
  final Duration _initialReconnectDelay;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Duration _reconnectDelay;

  ChatNotifier(
    this.streamId,
    this._accessToken, {
    ChatChannelFactory? channelFactory,
    bool connectOnInit = true,
    Duration reconnectDelay = initialReconnectDelay,
  })  : _channelFactory = channelFactory ?? WebSocketChannel.connect,
        _initialReconnectDelay = reconnectDelay,
        _reconnectDelay = reconnectDelay,
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    state = state.copyWith(isConnecting: true, statusText: 'Connexion…');

    try {
      // L'access token ne vit que 15 min : renouvelé au besoin avant la
      // poignée de main. Contrairement aux appels REST, le WebSocket n'a
      // pas d'intercepteur pour rejouer sur un 401 : un token périmé
      // laissait le chat « indisponible » pour tout le live.
      final token = await _accessToken();
      if (!mounted) return;
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
      _reconnectDelay = _initialReconnectDelay;

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
      if (!mounted) return;
      state = state.copyWith(
          isConnecting: false, statusText: 'Chat indisponible');
      _scheduleReconnect();
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
    // 1001 = le diffuseur a arrêté le live, le salon est fermé pour de bon.
    final liveEnded = _channel?.closeCode == 1001;
    state = state.copyWith(
      isConnected: false,
      isConnecting: false,
      statusText: liveEnded ? 'Le live est terminé' : reason,
    );
    if (!liveEnded) _scheduleReconnect();
  }

  /// Une coupure (réseau, app revenue de l'arrière-plan, serveur redémarré)
  /// ne doit pas laisser le chat mort jusqu'à ce qu'on quitte l'écran.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, connect);
    _reconnectDelay *= 2;
    if (_reconnectDelay > maxReconnectDelay) {
      _reconnectDelay = maxReconnectDelay;
    }
  }

  /// Envoie un message ; l'auteur et l'horodatage sont posés côté serveur.
  void send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !state.isConnected) return;
    _channel?.sink.add(jsonEncode({'text': trimmed}));
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}

/// Un salon (et une connexion WebSocket) par flux, fermé automatiquement
/// quand plus personne n'affiche le chat (autoDispose).
final chatProvider = StateNotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, String>((ref, streamId) {
  return ChatNotifier(
      streamId, ref.read(sessionRefresherProvider).validAccessToken);
});
