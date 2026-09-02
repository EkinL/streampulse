import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import 'package:streampulse/app/constants.dart';
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/features/music/domain/music_model.dart';
import 'package:streampulse/shared/providers/player_provider.dart';

class _FakeHandler extends Fake implements StreamPulseAudioHandler {
  final position = StreamController<Duration>.broadcast();
  final duration = StreamController<Duration?>.broadcast();
  final playing = StreamController<bool>.broadcast();
  final processing = StreamController<ProcessingState>.broadcast();
  final volumeCtrl = StreamController<double>.broadcast();

  final loaded = <(MediaItem, String)>[];
  final calls = <String>[];
  Duration? lastSeek;
  double? lastVolume;

  @override
  VoidCallback? onSkipToNext;
  @override
  VoidCallback? onSkipToPrevious;

  @override
  Stream<Duration> get positionStream => position.stream;
  @override
  Stream<Duration?> get durationStream => duration.stream;
  @override
  Stream<bool> get playingStream => playing.stream;
  @override
  Stream<ProcessingState> get processingStateStream => processing.stream;
  @override
  Stream<double> get volumeStream => volumeCtrl.stream;

  @override
  Future<Duration?> loadTrack(MediaItem item, String url) async {
    loaded.add((item, url));
    calls.add('load');
    return null;
  }

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration p) async {
    calls.add('seek');
    lastSeek = p;
  }

  @override
  Future<void> setVolume(double v) async => lastVolume = v;

  Future<void> close() async {
    await position.close();
    await duration.close();
    await playing.close();
    await processing.close();
    await volumeCtrl.close();
  }
}

MusicModel _track(String id, {String url = '', int duration = 120}) =>
    MusicModel(
      id: id,
      title: 'Track $id',
      artist: 'Artist',
      album: '',
      duration: duration,
      url: url.isEmpty ? '/music/$id/file' : url,
      uploadedBy: 'u',
      createdAt: DateTime(2026),
    );

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeHandler handler;
  late PlayerNotifier notifier;

  setUp(() {
    handler = _FakeHandler();
    notifier = PlayerNotifier(handler, initialVolume: 0.5);
  });

  tearDown(() async {
    notifier.dispose();
    await handler.close();
  });

  test('applique le volume initial et branche les callbacks systeme', () {
    expect(handler.lastVolume, 0.5);
    expect(notifier.state.volume, 0.5);
    expect(handler.onSkipToNext, isNotNull);
    expect(handler.onSkipToPrevious, isNotNull);
  });

  test('play charge la piste avec une URL absolue et un MediaItem', () async {
    await notifier.play(_track('a'));

    expect(handler.loaded, hasLength(1));
    final (item, url) = handler.loaded.single;
    expect(url, '${AppConstants.apiBaseUrl}/music/a/file');
    expect(item.id, 'a');
    expect(item.title, 'Track a');
    expect(item.artist, 'Artist');
    expect(item.duration, const Duration(seconds: 120));
    expect(handler.calls, ['load', 'play']);
    expect(notifier.state.currentTrack?.id, 'a');
    expect(notifier.state.queue, hasLength(1));
  });

  test('une URL deja absolue est conservee', () async {
    await notifier.play(_track('a', url: 'https://cdn/x.mp3'));
    expect(handler.loaded.single.$2, 'https://cdn/x.mp3');
  });

  test('playPlaylist borne l\'index de depart', () async {
    final tracks = [_track('a'), _track('b'), _track('c')];

    await notifier.playPlaylist(tracks, 42);

    expect(notifier.state.queueIndex, 2);
    expect(notifier.state.currentTrack?.id, 'c');
    expect(notifier.state.hasNext, isFalse);
    expect(notifier.state.hasPrevious, isTrue);
  });

  test('playPlaylist vide ne fait rien', () async {
    await notifier.playPlaylist([], 0);
    expect(handler.calls, isEmpty);
  });

  test('next avance dans la file, s\'arrete en fin', () async {
    await notifier.playPlaylist([_track('a'), _track('b')], 0);

    await notifier.next();
    expect(notifier.state.currentTrack?.id, 'b');

    await notifier.next();
    expect(notifier.state.currentTrack?.id, 'b');
    expect(handler.loaded, hasLength(2));
  });

  test('previous redemarre la piste au-dela de 3 s', () async {
    await notifier.playPlaylist([_track('a'), _track('b')], 1);
    handler.position.add(const Duration(seconds: 10));
    await _flush();

    await notifier.previous();

    expect(handler.lastSeek, Duration.zero);
    expect(notifier.state.currentTrack?.id, 'b');
  });

  test('previous revient a la piste precedente sous 3 s', () async {
    await notifier.playPlaylist([_track('a'), _track('b')], 1);
    handler.position.add(const Duration(seconds: 1));
    await _flush();

    await notifier.previous();

    expect(notifier.state.currentTrack?.id, 'a');
    expect(notifier.state.queueIndex, 0);
  });

  test('les controles systeme pilotent la file', () async {
    await notifier.playPlaylist([_track('a'), _track('b')], 0);

    handler.onSkipToNext!();
    await _flush();
    expect(notifier.state.currentTrack?.id, 'b');

    handler.onSkipToPrevious!();
    await _flush();
    expect(notifier.state.currentTrack?.id, 'a');
  });

  test('fin de piste : enchaine la suivante', () async {
    await notifier.playPlaylist([_track('a'), _track('b')], 0);

    handler.processing.add(ProcessingState.completed);
    await _flush();

    expect(notifier.state.currentTrack?.id, 'b');
  });

  test('fin de file : pause et retour au debut', () async {
    await notifier.play(_track('a'));
    handler.calls.clear();

    handler.processing.add(ProcessingState.completed);
    await _flush();

    expect(handler.calls, ['pause', 'seek']);
    expect(handler.lastSeek, Duration.zero);
    expect(notifier.state.isPlaying, isFalse);
    expect(notifier.state.currentTrack?.id, 'a');
  });

  test('togglePlayPause suit l\'etat de lecture', () async {
    handler.playing.add(true);
    await _flush();
    await notifier.togglePlayPause();
    expect(handler.calls.last, 'pause');

    handler.playing.add(false);
    await _flush();
    await notifier.togglePlayPause();
    expect(handler.calls.last, 'play');
  });

  test('l\'etat suit position, duree et volume du lecteur', () async {
    handler.position.add(const Duration(seconds: 3));
    handler.duration.add(const Duration(minutes: 2));
    handler.volumeCtrl.add(0.25);
    await _flush();

    expect(notifier.state.position, const Duration(seconds: 3));
    expect(notifier.state.duration, const Duration(minutes: 2));
    expect(notifier.state.volume, 0.25);
  });

  test('stop reinitialise tout sauf le volume', () async {
    await notifier.play(_track('a'));
    handler.volumeCtrl.add(0.3);
    await _flush();

    await notifier.stop();

    expect(handler.calls.last, 'stop');
    expect(notifier.state.currentTrack, isNull);
    expect(notifier.state.queue, isEmpty);
    expect(notifier.state.volume, 0.3);
  });

  test('dispose detache ses callbacks du handler', () {
    notifier.dispose();
    expect(handler.onSkipToNext, isNull);
    expect(handler.onSkipToPrevious, isNull);
    notifier = PlayerNotifier(handler, initialVolume: 0.5);
  });

  group('mode offline', () {
    test('joue le fichier local quand la piste est telechargee', () async {
      notifier.dispose();
      notifier = PlayerNotifier(
        handler,
        initialVolume: 0.5,
        localPathResolver: (trackId) async =>
            trackId == 'a' ? '/data/offline_audio/a.mp3' : null,
      );

      await notifier.play(_track('a'));

      final (_, url) = handler.loaded.single;
      expect(url, Uri.file('/data/offline_audio/a.mp3').toString());
    });

    test('retombe sur l\'URL reseau quand la piste n\'est pas en cache',
        () async {
      notifier.dispose();
      notifier = PlayerNotifier(
        handler,
        initialVolume: 0.5,
        localPathResolver: (_) async => null,
      );

      await notifier.play(_track('a'));

      final (_, url) = handler.loaded.single;
      expect(url, '${AppConstants.apiBaseUrl}/music/a/file');
    });
  });
}
