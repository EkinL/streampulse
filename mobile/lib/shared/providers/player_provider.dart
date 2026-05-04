import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../app/constants.dart';
import '../../features/music/domain/music_model.dart';

class PlayerState {
  final MusicModel? currentTrack;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<MusicModel> queue;
  final int queueIndex;

  const PlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.queue = const [],
    this.queueIndex = 0,
  });

  PlayerState copyWith({
    MusicModel? currentTrack,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    List<MusicModel>? queue,
    int? queueIndex,
  }) {
    return PlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
    );
  }
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  final AudioPlayer _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  PlayerNotifier(this._player) : super(const PlayerState()) {
    _subscriptions.add(
      _player.positionStream.listen((pos) {
        if (mounted) state = state.copyWith(position: pos);
      }),
    );
    _subscriptions.add(
      _player.durationStream.listen((dur) {
        if (mounted && dur != null) {
          state = state.copyWith(duration: dur);
        }
      }),
    );
    _subscriptions.add(
      _player.playerStateStream.listen((playerState) {
        if (!mounted) return;
        final playing = playerState.playing;
        state = state.copyWith(isPlaying: playing);

        if (playerState.processingState == ProcessingState.completed) {
          _onTrackCompleted();
        }
      }),
    );
  }

  String _resolveUrl(String url) {
    if (url.startsWith('/')) {
      return '${AppConstants.apiBaseUrl}$url';
    }
    return url;
  }

  Future<void> play(MusicModel track) async {
    final url = _resolveUrl(track.url);
    await _player.setUrl(url);
    state = state.copyWith(
      currentTrack: track,
      queue: [track],
      queueIndex: 0,
      position: Duration.zero,
    );
    await _player.play();
  }

  Future<void> playPlaylist(List<MusicModel> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    final index = startIndex.clamp(0, tracks.length - 1);
    final track = tracks[index];
    final url = _resolveUrl(track.url);
    await _player.setUrl(url);
    state = state.copyWith(
      currentTrack: track,
      queue: tracks,
      queueIndex: index,
      position: Duration.zero,
    );
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    await _player.play();
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  Future<void> next() async {
    if (state.queue.isEmpty) return;
    final nextIndex = state.queueIndex + 1;
    if (nextIndex < state.queue.length) {
      final track = state.queue[nextIndex];
      final url = _resolveUrl(track.url);
      await _player.setUrl(url);
      state = state.copyWith(
        currentTrack: track,
        queueIndex: nextIndex,
        position: Duration.zero,
      );
      await _player.play();
    }
  }

  Future<void> previous() async {
    if (state.queue.isEmpty) return;
    // If more than 3 seconds in, restart current track
    if (state.position.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }
    final prevIndex = state.queueIndex - 1;
    if (prevIndex >= 0) {
      final track = state.queue[prevIndex];
      final url = _resolveUrl(track.url);
      await _player.setUrl(url);
      state = state.copyWith(
        currentTrack: track,
        queueIndex: prevIndex,
        position: Duration.zero,
      );
      await _player.play();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    state = const PlayerState();
  }

  void _onTrackCompleted() {
    if (state.queueIndex + 1 < state.queue.length) {
      next();
    } else {
      state = state.copyWith(isPlaying: false);
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}

final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  final player = AudioPlayer();
  ref.onDispose(player.dispose);
  return PlayerNotifier(player);
});
