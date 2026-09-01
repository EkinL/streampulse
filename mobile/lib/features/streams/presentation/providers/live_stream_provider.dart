import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sound/flutter_sound.dart';
import '../../../../app/constants.dart';
import '../../../../core/audio/audio_handler.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../shared/providers/volume_provider.dart';

class LiveStreamState {
  final String? streamId;
  /// Titre du flux — mémorisé pour le mini-lecteur persistant, qui reste
  /// visible sur des écrans (Playlists, Favoris) sans accès à ses propres
  /// données de flux.
  final String? title;
  final bool isConnected;
  final bool isConnecting;
  final bool isReceivingData;
  final int bytesReceived;
  final String statusText;

  const LiveStreamState({
    this.streamId,
    this.title,
    this.isConnected = false,
    this.isConnecting = false,
    this.isReceivingData = false,
    this.bytesReceived = 0,
    this.statusText = 'Tap play to listen',
  });

  LiveStreamState copyWith({
    String? streamId,
    String? title,
    bool? isConnected,
    bool? isConnecting,
    bool? isReceivingData,
    int? bytesReceived,
    String? statusText,
  }) {
    return LiveStreamState(
      streamId: streamId ?? this.streamId,
      title: title ?? this.title,
      isConnected: isConnected ?? this.isConnected,
      isConnecting: isConnecting ?? this.isConnecting,
      isReceivingData: isReceivingData ?? this.isReceivingData,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      statusText: statusText ?? this.statusText,
    );
  }
}

class LiveStreamNotifier extends StateNotifier<LiveStreamState> {
  final SecureStorageService _secureStorage;

  final StreamPulseAudioHandler? _audioHandler;

  HttpClient? _httpClient;
  StreamSubscription? _dataSub;
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _playerReady = false;
  double _volume;

  LiveStreamNotifier(
    this._secureStorage, {
    StreamPulseAudioHandler? audioHandler,
    double initialVolume = AppConstants.defaultVolume,
  })  : _audioHandler = audioHandler,
        _volume = initialVolume,
        super(const LiveStreamState()) {
    _audioHandler?.onLiveStop = _onSystemStop;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    _playerReady = true;
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_playerReady && _player.isPlaying) {
      await _player.setVolume(_volume);
    }
  }

  void _onSystemStop() {
    if (mounted && (state.isConnected || state.isConnecting)) {
      disconnect(reason: 'Stopped');
    }
  }

  Future<void> connect(String streamId, {String? title}) async {
    if (state.isConnecting || state.isConnected) return;

    if (!_playerReady) {
      await _initPlayer();
    }

    state = LiveStreamState(
      streamId: streamId,
      title: title,
      isConnecting: true,
      statusText: 'Connecting...',
    );

    try {
      final token = await _secureStorage.getAccessToken();
      final uri = Uri.parse(
        '${AppConstants.apiBaseUrl}${ApiEndpoints.stream(streamId)}/audio',
      );

      _httpClient = HttpClient();
      _httpClient!.connectionTimeout = const Duration(seconds: 15);

      final request = await _httpClient!.getUrl(uri);
      request.headers.set('Authorization', 'Bearer $token');

      final response = await request.close();

      if (response.statusCode != 200) {
        String msg = 'Connection failed (${response.statusCode})';
        if (response.statusCode == 400) msg = 'Stream is not live';
        if (response.statusCode == 401) msg = 'Session expired';
        throw HttpException(msg);
      }

      // iOS route le son selon la session audio active. Sans configuration,
      // la categorie par defaut (soloAmbient) est coupee par l'interrupteur
      // silencieux, et une session posee par un recorder (playAndRecord)
      // sort sur l'ecouteur telephonique, pas le haut-parleur.
      // Playback = haut-parleur, insensible a l'interrupteur, comme la musique.
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);

      // Start PCM player stream - matches recorder: PCM16, 16kHz, mono.
      // interleaved: true est obligatoire pour alimenter uint8ListSink.
      // En interleaved: false, flutter_sound attend int16Sink/float32Sink et
      // uint8ListSink vaut null : les donnees partent a la poubelle en silence.
      await _player.startPlayerFromStream(
        codec: Codec.pcm16,
        interleaved: true,
        sampleRate: 16000,
        numChannels: 1,
        bufferSize: 8192,
      );
      await _player.setVolume(_volume);

      // session media : l'OS garde l'app en vie en arriere-plan + bouton stop
      await _audioHandler?.startLive(
        MediaItem(
          id: 'live:$streamId',
          title: title ?? 'Live stream',
          artist: 'StreamPulse - Live',
          isLive: true,
        ),
      );

      state = state.copyWith(
        isConnected: true,
        isConnecting: false,
        statusText: 'Connected - Waiting for audio...',
      );

      _dataSub = response.listen(
        (List<int> chunk) {
          if (!mounted) return;

          final bytes = Uint8List.fromList(chunk);
          final newTotal = state.bytesReceived + bytes.length;

          // Feed audio data to player
          _player.uint8ListSink?.add(bytes);

          state = state.copyWith(
            isReceivingData: true,
            bytesReceived: newTotal,
            statusText:
                'Playing (${(newTotal / 1024).toStringAsFixed(0)} KB)',
          );
        },
        onError: (error) {
          if (mounted) disconnect(reason: 'Connection lost');
        },
        onDone: () {
          if (mounted) disconnect(reason: 'Stream ended');
        },
        cancelOnError: true,
      );
    } on HttpException catch (e) {
      if (mounted) {
        state = LiveStreamState(
          streamId: streamId,
          title: title,
          statusText: e.message,
        );
      }
    } catch (e) {
      if (mounted) {
        state = LiveStreamState(
          streamId: streamId,
          title: title,
          statusText: 'Connection failed',
        );
        debugPrint('Audio stream error: $e');
      }
    }
  }

  void disconnect({String reason = 'Disconnected'}) {
    _dataSub?.cancel();
    _dataSub = null;
    _httpClient?.close(force: true);
    _httpClient = null;

    if (_playerReady && _player.isPlaying) {
      _player.stopPlayer();
    }
    _audioHandler?.stopLive();

    if (mounted) {
      state = LiveStreamState(
        streamId: state.streamId,
        title: state.title,
        statusText: reason,
      );
    }
  }

  /// Called when the stream goes offline externally.
  void onStreamEnded() {
    if (state.isConnected) {
      disconnect(reason: 'Stream ended');
    }
  }

  /// Called when a stream comes online.
  void onStreamLive(String streamId) {
    if (!state.isConnected && !state.isConnecting) {
      state = state.copyWith(
        streamId: streamId,
        statusText: 'Stream is live! Tap to listen',
      );
    }
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _httpClient?.close(force: true);
    if (_playerReady) {
      _player.closePlayer();
    }
    if (_audioHandler?.onLiveStop == _onSystemStop) {
      _audioHandler?.onLiveStop = null;
    }
    super.dispose();
  }
}

final liveStreamProvider =
    StateNotifierProvider<LiveStreamNotifier, LiveStreamState>((ref) {
  final secureStorage = ref.read(secureStorageProvider);
  final notifier = LiveStreamNotifier(
    secureStorage,
    audioHandler: ref.watch(audioHandlerProvider),
    initialVolume: ref.read(volumeProvider),
  );
  ref.listen<double>(volumeProvider, (_, v) => notifier.setVolume(v));
  return notifier;
});
