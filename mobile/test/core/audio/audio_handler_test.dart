import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';

import 'package:streampulse/core/audio/audio_handler.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  late _MockAudioPlayer player;
  late StreamController<PlaybackEvent> events;
  late StreamPulseAudioHandler handler;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    player = _MockAudioPlayer();
    events = StreamController<PlaybackEvent>.broadcast();
    when(() => player.playbackEventStream).thenAnswer((_) => events.stream);
    when(() => player.playing).thenReturn(false);
    when(() => player.processingState).thenReturn(ProcessingState.idle);
    when(() => player.position).thenReturn(Duration.zero);
    when(() => player.bufferedPosition).thenReturn(Duration.zero);
    when(() => player.speed).thenReturn(1.0);
    when(() => player.volume).thenReturn(0.8);
    when(() => player.setUrl(any())).thenAnswer((_) async => null);
    when(() => player.play()).thenAnswer((_) async {});
    when(() => player.pause()).thenAnswer((_) async {});
    when(() => player.stop()).thenAnswer((_) async {});
    when(() => player.seek(any())).thenAnswer((_) async {});
    when(() => player.setVolume(any())).thenAnswer((_) async {});
    when(() => player.dispose()).thenAnswer((_) async {});
    handler = StreamPulseAudioHandler(player: player);
  });

  tearDown(() async {
    await events.close();
    await handler.dispose();
  });

  const item = MediaItem(id: '1', title: 'Track');

  group('mode piste', () {
    test('loadTrack publie le MediaItem et charge l\'URL', () async {
      await handler.loadTrack(item, 'http://x/a.mp3');

      expect(handler.mediaItem.value, item);
      verify(() => player.setUrl('http://x/a.mp3')).called(1);
    });

    test('les evenements just_audio deviennent un PlaybackState', () async {
      when(() => player.playing).thenReturn(true);
      when(() => player.processingState).thenReturn(ProcessingState.ready);
      when(() => player.position).thenReturn(const Duration(seconds: 12));

      events.add(PlaybackEvent(currentIndex: 0));
      await Future<void>.delayed(Duration.zero);

      final state = handler.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.processingState, AudioProcessingState.ready);
      expect(state.updatePosition, const Duration(seconds: 12));
      expect(state.controls, contains(MediaControl.pause));
      expect(state.controls, isNot(contains(MediaControl.play)));
      expect(state.systemActions, contains(MediaAction.seek));
    });

    test('play / pause / seek / setVolume delegent au lecteur', () async {
      await handler.play();
      await handler.pause();
      await handler.seek(const Duration(seconds: 5));
      await handler.setVolume(0.4);

      verify(() => player.play()).called(1);
      verify(() => player.pause()).called(1);
      verify(() => player.seek(const Duration(seconds: 5))).called(1);
      verify(() => player.setVolume(0.4)).called(1);
    });

    test('setVolume borne la valeur dans [0, 1]', () async {
      await handler.setVolume(1.7);
      await handler.setVolume(-3);

      verify(() => player.setVolume(1.0)).called(1);
      verify(() => player.setVolume(0.0)).called(1);
    });

    test('skipToNext / skipToPrevious appellent les callbacks', () async {
      var next = 0;
      var prev = 0;
      handler.onSkipToNext = () => next++;
      handler.onSkipToPrevious = () => prev++;

      await handler.skipToNext();
      await handler.skipToPrevious();

      expect(next, 1);
      expect(prev, 1);
    });

    test('stop vide le MediaItem', () async {
      await handler.loadTrack(item, 'http://x/a.mp3');
      await handler.stop();

      verify(() => player.stop()).called(1);
      expect(handler.mediaItem.value, isNull);
    });
  });

  group('mode live', () {
    const live = MediaItem(id: 'live:1', title: 'Radio', isLive: true);

    test('startLive annonce la lecture avec un seul controle stop', () async {
      await handler.startLive(live);

      expect(handler.isLive, isTrue);
      expect(handler.mediaItem.value, live);
      final state = handler.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.processingState, AudioProcessingState.ready);
      expect(state.controls, [MediaControl.stop]);
    });

    test('startLive arrete la piste en cours', () async {
      when(() => player.playing).thenReturn(true);

      await handler.startLive(live);

      verify(() => player.stop()).called(1);
    });

    test('les evenements just_audio sont ignores pendant le live', () async {
      await handler.startLive(live);
      when(() => player.processingState).thenReturn(ProcessingState.idle);

      events.add(PlaybackEvent());
      await Future<void>.delayed(Duration.zero);

      expect(handler.playbackState.value.playing, isTrue);
    });

    test('pause et stop systeme sont renvoyes a onLiveStop', () async {
      var stops = 0;
      handler.onLiveStop = () => stops++;
      await handler.startLive(live);

      await handler.pause();
      await handler.stop();
      await handler.play();

      expect(stops, 2);
      verifyNever(() => player.pause());
      verifyNever(() => player.play());
    });

    test('stopLive libere la session media', () async {
      await handler.startLive(live);
      await handler.stopLive();

      expect(handler.isLive, isFalse);
      expect(handler.mediaItem.value, isNull);
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.processingState,
          AudioProcessingState.idle);
    });

    test('loadTrack coupe le live avant de charger la piste', () async {
      var stops = 0;
      handler.onLiveStop = () {
        stops++;
        handler.stopLive();
      };
      await handler.startLive(live);

      await handler.loadTrack(item, 'http://x/a.mp3');

      expect(stops, 1);
      expect(handler.isLive, isFalse);
      expect(handler.mediaItem.value, item);
    });
  });
}
