import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import '../../app/constants.dart';
import '../../core/audio/audio_handler.dart';
import '../../features/music/domain/music_model.dart';
import 'offline_provider.dart';
import 'volume_provider.dart';

class PlayerState {
  final MusicModel? currentTrack;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<MusicModel> queue;
  final int queueIndex;

  final double volume;

  const PlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.queueIndex = 0,
    this.volume = AppConstants.defaultVolume,
  });

  bool get hasNext => queueIndex + 1 < queue.length;
  bool get hasPrevious => queueIndex > 0;

  PlayerState copyWith({
    MusicModel? currentTrack,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<MusicModel>? queue,
    int? queueIndex,
    double? volume,
  }) {
    return PlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      volume: volume ?? this.volume,
    );
  }
}

/// File d'attente du lecteur de pistes, la lecture passe par le handler.
class PlayerNotifier extends StateNotifier<PlayerState> {
  final StreamPulseAudioHandler _handler;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Mode offline : renvoie le chemin local d'une piste telechargee, ou null.
  final Future<String?> Function(String trackId)? localPathResolver;

  PlayerNotifier(
    this._handler, {
    double initialVolume = AppConstants.defaultVolume,
    this.localPathResolver,
  }) : super(PlayerState(volume: initialVolume)) {
    _handler
      ..onSkipToNext = next
      ..onSkipToPrevious = previous;

    _subscriptions.add(
      _handler.positionStream.listen((pos) {
        if (mounted) state = state.copyWith(position: pos);
      }),
    );
    _subscriptions.add(
      _handler.durationStream.listen((dur) {
        if (mounted && dur != null) state = state.copyWith(duration: dur);
      }),
    );
    _subscriptions.add(
      _handler.playingStream.listen((playing) {
        if (mounted) state = state.copyWith(isPlaying: playing);
      }),
    );
    _subscriptions.add(
      _handler.processingStateStream.listen((processing) {
        if (mounted && processing == ProcessingState.completed) {
          _onTrackCompleted();
        }
      }),
    );
    _subscriptions.add(
      _handler.volumeStream.listen((v) {
        if (mounted) state = state.copyWith(volume: v);
      }),
    );

    _handler.setVolume(initialVolume);
  }

  String _resolveUrl(String url) {
    if (url.startsWith('/')) {
      return '${AppConstants.apiBaseUrl}$url';
    }
    return url;
  }

  MediaItem _toMediaItem(MusicModel track) {
    final cover = track.coverUrl;
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist.isNotEmpty ? track.artist : null,
      album: track.album.isNotEmpty ? track.album : null,
      duration: track.duration > 0 ? Duration(seconds: track.duration) : null,
      artUri: cover != null && cover.isNotEmpty
          ? Uri.tryParse(_resolveUrl(cover))
          : null,
    );
  }

  Future<void> _load(List<MusicModel> queue, int index) async {
    final track = queue[index];
    // Piste telechargee ? On joue le fichier local (ecoute hors ligne).
    final localPath = await localPathResolver?.call(track.id);
    final source = localPath != null
        ? Uri.file(localPath).toString()
        : _resolveUrl(track.url);
    await _handler.loadTrack(_toMediaItem(track), source);
    state = state.copyWith(
      currentTrack: track,
      queue: queue,
      queueIndex: index,
      position: Duration.zero,
    );
    await _handler.play();
  }

  Future<void> play(MusicModel track) => _load([track], 0);

  Future<void> playPlaylist(List<MusicModel> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    await _load(tracks, startIndex.clamp(0, tracks.length - 1));
  }

  Future<void> pause() => _handler.pause();

  Future<void> resume() => _handler.play();

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> seekTo(Duration position) => _handler.seek(position);

  Future<void> setVolume(double volume) => _handler.setVolume(volume);

  Future<void> next() async {
    if (!state.hasNext) return;
    await _load(state.queue, state.queueIndex + 1);
  }

  Future<void> previous() async {
    if (state.queue.isEmpty) return;
    // au-dela de 3s, precedent = redemarrer la piste
    if (state.position.inSeconds > 3 || !state.hasPrevious) {
      await seekTo(Duration.zero);
      return;
    }
    await _load(state.queue, state.queueIndex - 1);
  }

  Future<void> stop() async {
    await _handler.stop();
    state = PlayerState(volume: state.volume);
  }

  Future<void> _onTrackCompleted() async {
    if (state.hasNext) {
      await next();
      return;
    }
    // fin de file : retour au debut, pret a rejouer
    await _handler.pause();
    await _handler.seek(Duration.zero);
    // le notifier a pu etre dispose pendant les await ci-dessus
    if (!mounted) return;
    state = state.copyWith(isPlaying: false, position: Duration.zero);
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    if (_handler.onSkipToNext == next) _handler.onSkipToNext = null;
    if (_handler.onSkipToPrevious == previous) _handler.onSkipToPrevious = null;
    super.dispose();
  }
}

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final notifier = PlayerNotifier(
    handler,
    initialVolume: ref.read(volumeProvider),
    localPathResolver: (trackId) =>
        ref.read(offlineProvider.notifier).localPathFor(trackId),
  );
  ref.listen<double>(volumeProvider, (_, v) => notifier.setVolume(v));
  return notifier;
});
