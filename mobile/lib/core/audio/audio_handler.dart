import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Session media de l'app (audio_service) : lecture en arriere-plan,
/// notification, controles ecran verrouille / casque.
///
/// Deux modes exclusifs :
///  - piste : just_audio lit une URL, ses evenements sont traduits en PlaybackState
///  - live : flutter_sound joue le PCM (LiveStreamNotifier), ici on ne fait que
///    declarer la session "en lecture" pour que l'OS garde le process en vie.
class StreamPulseAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;
  VoidCallback? onLiveStop;

  bool _liveMode = false;
  bool _resumeAfterInterruption = false;
  double? _volumeBeforeDuck;

  StreamPulseAudioHandler({AudioPlayer? player})
      : _player = player ?? AudioPlayer() {
    _subscriptions.add(
      _player.playbackEventStream.listen(
        (event) {
          if (!_liveMode) playbackState.add(_transformEvent(event));
        },
        onError: (Object e, StackTrace st) {
          debugPrint('audio: playback error $e');
        },
      ),
    );
  }

  /// Session "music" (haut-parleur, ignore l'interrupteur silencieux) +
  /// interruptions : appel, autre app audio, casque debranche.
  Future<void> init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _subscriptions.add(session.interruptionEventStream.listen(_onInterruption));
    _subscriptions.add(session.becomingNoisyEventStream.listen((_) => pause()));
  }

  bool get isLive => _liveMode;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;
  Stream<double> get volumeStream => _player.volumeStream;
  double get volume => _player.volume;

  // --- Mode piste

  Future<Duration?> loadTrack(MediaItem item, String url) async {
    if (_liveMode) onLiveStop?.call();
    mediaItem.add(item);
    return _player.setUrl(url);
  }

  @override
  Future<void> play() async {
    if (_liveMode) return;
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (_liveMode) {
      onLiveStop?.call();
      return;
    }
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    if (_liveMode) {
      onLiveStop?.call();
      return;
    }
    await _player.stop();
    mediaItem.add(null);
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async => onSkipToNext?.call();

  @override
  Future<void> skipToPrevious() async => onSkipToPrevious?.call();

  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  // --- Mode live

  Future<void> startLive(MediaItem item) async {
    if (_player.playing) await _player.stop();
    _liveMode = true;
    mediaItem.add(item);
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [MediaControl.stop],
        systemActions: const {},
        androidCompactActionIndices: const [0],
        processingState: AudioProcessingState.ready,
        playing: true,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      ),
    );
  }

  Future<void> stopLive() async {
    if (!_liveMode) return;
    _liveMode = false;
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    mediaItem.add(null);
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (!_liveMode) {
            _volumeBeforeDuck = _player.volume;
            _player.setVolume(_player.volume * 0.3);
          }
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (_liveMode) {
            // un live ne se met pas en pause
            onLiveStop?.call();
          } else if (_player.playing) {
            _resumeAfterInterruption =
                event.type == AudioInterruptionType.pause;
            _player.pause();
          }
      }
      return;
    }

    switch (event.type) {
      case AudioInterruptionType.duck:
        final previous = _volumeBeforeDuck;
        _volumeBeforeDuck = null;
        if (previous != null) _player.setVolume(previous);
      case AudioInterruptionType.pause:
        if (_resumeAfterInterruption) _player.play();
        _resumeAfterInterruption = false;
      case AudioInterruptionType.unknown:
        _resumeAfterInterruption = false;
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _player.dispose();
  }
}

/// Surcharge dans le ProviderScope racine (main.dart), faux en test.
final audioHandlerProvider = Provider<StreamPulseAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider non surcharge');
});
