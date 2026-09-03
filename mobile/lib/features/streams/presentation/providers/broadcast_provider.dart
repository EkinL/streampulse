import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../app/constants.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/session_refresher.dart';

/// Fournit un access token valide pour la poignee de main, null sans session.
typedef BroadcastTokenProvider = Future<String?> Function();

/// Etat de la capture micro du diffuseur.
class BroadcastState {
  final String? streamId;
  final bool isBroadcasting;

  /// Vrai quand la connexion vers le backend est ouverte : les chunks du
  /// micro partent reellement vers les auditeurs. Faux pendant la poignee
  /// de main et entre une coupure et la reconnexion.
  final bool isConnected;

  /// Passage a l'antenne, pour le compteur de duree de la console.
  final DateTime? startedAt;

  /// Coupures de l'envoi vers le backend depuis le passage a l'antenne.
  final int dropCount;

  const BroadcastState({
    this.streamId,
    this.isBroadcasting = false,
    this.isConnected = false,
    this.startedAt,
    this.dropCount = 0,
  });

  bool isBroadcastingStream(String id) => isBroadcasting && streamId == id;

  BroadcastState copyWith({bool? isConnected, int? dropCount}) =>
      BroadcastState(
        streamId: streamId,
        isBroadcasting: isBroadcasting,
        isConnected: isConnected ?? this.isConnected,
        startedAt: startedAt,
        dropCount: dropCount ?? this.dropCount,
      );
}

/// Capture le micro et le pousse au backend en WebSocket
/// (/streams/:id/broadcast/ws, une trame binaire par chunk) pendant toute
/// la duree du live.
///
/// WebSocket et non POST chunke : dans un navigateur (console web),
/// XMLHttpRequest accumule tout le corps d'une requete en memoire et ne
/// l'envoie qu'une fois le flux termine, c'est-a-dire a la fin du live. Les
/// auditeurs restaient sur « Waiting for audio ». Une trame WebSocket part
/// tout de suite, sur mobile comme sur le web, et traverse le reverse proxy.
///
/// Vit dans un provider, pas dans l'ecran de la console : la console est une
/// route pleine page, la quitter (retour a la liste, detail d'un flux)
/// detruisait l'ecran et avec lui la capture, alors que le flux restait
/// "live" cote serveur. Les auditeurs se connectaient a un direct muet.
/// Symetrique de LiveStreamNotifier pour l'ecoute.
class BroadcastNotifier extends StateNotifier<BroadcastState> {
  final BroadcastTokenProvider _accessToken;
  final AudioRecorder _recorder;
  final String _baseUrl;
  final Duration _retryDelay;

  StreamSubscription<Uint8List>? _micSub;
  WebSocketChannel? _channel;

  /// Incremente a chaque start/stop : une reconnexion en cours qui ne porte
  /// plus le numero courant se sait obsolete et s'arrete d'elle-meme.
  int _session = 0;

  BroadcastNotifier(
    this._accessToken, {
    AudioRecorder? recorder,
    String baseUrl = AppConstants.apiBaseUrl,
    // Doit rester sous BROADCAST_GRACE_PERIOD (10 s) cote serveur, sinon le
    // direct est arrete avant que la connexion soit rouverte.
    Duration retryDelay = const Duration(seconds: 2),
  }) : _recorder = recorder ?? AudioRecorder(),
       _baseUrl = baseUrl,
       _retryDelay = retryDelay,
       super(const BroadcastState());

  /// URL de l'ingest : meme hote (et meme prefixe de chemin, comme Dio) que
  /// l'API, schema ws(s). Le token passe en parametre de requete, seul canal
  /// d'auth commun a toutes les plateformes (un WebSocket navigateur ne peut
  /// pas poser de header).
  static Uri broadcastUri(String baseUrl, String streamId, String token) {
    final base = Uri.parse(baseUrl);
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$prefix${ApiEndpoints.streamBroadcast(streamId)}/ws',
      queryParameters: {'token': token},
    );
  }

  /// Demarre la capture pour [streamId]. Renvoie false si la permission
  /// micro est refusee (rien n'est demarre). Sans effet si ce flux est deja
  /// a l'antenne ; un autre flux en cours est coupe d'abord.
  Future<bool> start(String streamId) async {
    if (state.isBroadcastingStream(streamId)) return true;
    if (state.isBroadcasting) await stop();

    if (!await _recorder.hasPermission()) return false;

    // PCM16 16 kHz mono : le lecteur des auditeurs (LiveStreamNotifier)
    // attend exactement ce format.
    final mic = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    state = BroadcastState(
      streamId: streamId,
      isBroadcasting: true,
      startedAt: DateTime.now(),
    );

    // Micro mort (plugin en erreur) : on quitte l'antenne, le serveur
    // arretera le direct faute de diffuseur.
    _micSub = mic.listen(_send, onDone: stop, onError: (Object _) => stop());
    unawaited(_openUpload(streamId, ++_session));
    return true;
  }

  void _send(Uint8List data) {
    final channel = _channel;
    // Reconnexion en cours : ce chunk est perdu, c'est la coupure.
    if (channel == null) return;
    try {
      channel.sink.add(data);
    } catch (e) {
      // Socket deja fermee cote serveur : _openUpload va la rouvrir.
      debugPrint('broadcast frame dropped: $e');
    }
  }

  /// Ouvre la connexion et y branche le micro. Si elle tombe alors qu'on est
  /// toujours a l'antenne, on la rouvre : une seule coupure (backend
  /// redemarre, reseau) ne doit pas laisser un direct muet jusqu'a l'arret
  /// manuel.
  Future<void> _openUpload(String streamId, int session) async {
    bool current() =>
        mounted && session == _session && state.isBroadcastingStream(streamId);

    Object? failure;
    WebSocketChannel? channel;
    try {
      // L'access token ne vit que 15 min : renouvele au besoin avant la
      // poignee de main, sinon une reconnexion tardive serait refusee (401).
      final token = await _accessToken();
      if (!current()) return;
      if (token == null) throw StateError('no session');

      channel = WebSocketChannel.connect(broadcastUri(_baseUrl, streamId, token));
      await channel.ready;
      if (!current()) {
        unawaited(channel.sink.close().catchError((_) {}));
        return;
      }
      // Une socket qui casse signale aussi l'erreur sur `done` : sans
      // personne pour l'ecouter, elle remonterait comme erreur non geree.
      unawaited(channel.sink.done.catchError((_) {}));
      _channel = channel;
      state = state.copyWith(isConnected: true);

      // Le serveur n'envoie rien : on n'ecoute que pour savoir quand la
      // connexion tombe.
      await channel.stream.drain<void>();
    } catch (e) {
      failure = e;
    }

    if (_channel == channel) _channel = null;
    // Arret volontaire entre-temps : rien a faire.
    if (!current()) return;
    debugPrint('broadcast upload ended: ${failure ?? 'closed by server'}');
    state = state.copyWith(
      isConnected: false,
      dropCount: state.dropCount + 1,
    );

    await Future<void>.delayed(_retryDelay);
    if (current()) await _openUpload(streamId, session);
  }

  Future<void> stop() async {
    _session++;
    await _micSub?.cancel();
    _micSub = null;
    _closeChannel();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    if (mounted) state = const BroadcastState();
  }

  /// Pas de await sur la fermeture : elle attend la reponse du serveur, et
  /// couper l'antenne ne doit pas en dependre.
  void _closeChannel() {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      unawaited(channel.sink.close().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    _session++;
    _micSub?.cancel();
    _closeChannel();
    _recorder.dispose();
    super.dispose();
  }
}

final broadcastProvider =
    StateNotifierProvider<BroadcastNotifier, BroadcastState>((ref) {
      return BroadcastNotifier(
        ref.read(sessionRefresherProvider).validAccessToken,
      );
    });
