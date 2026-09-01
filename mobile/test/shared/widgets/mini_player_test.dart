import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/features/music/domain/music_model.dart';
import 'package:streampulse/shared/providers/player_provider.dart';
import 'package:streampulse/shared/widgets/mini_player.dart';

class _FakeHandler extends Fake implements StreamPulseAudioHandler {
  final position = StreamController<Duration>.broadcast();
  final duration = StreamController<Duration?>.broadcast();
  final playing = StreamController<bool>.broadcast();
  final processing = StreamController<ProcessingState>.broadcast();
  final volumeCtrl = StreamController<double>.broadcast();

  final calls = <String>[];

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
  Future<void> seek(Duration p) async => calls.add('seek');
  @override
  Future<void> setVolume(double v) async {}

  Future<void> close() async {
    await position.close();
    await duration.close();
    await playing.close();
    await processing.close();
    await volumeCtrl.close();
  }
}

MusicModel _track({String title = 'Track', String artist = 'Artist'}) => MusicModel(
      id: 'm1',
      title: title,
      artist: artist,
      album: '',
      duration: 120,
      url: '/music/m1/file',
      uploadedBy: 'u1',
      createdAt: DateTime(2026),
    );

void main() {
  late _FakeHandler handler;
  late PlayerNotifier notifier;

  setUp(() {
    handler = _FakeHandler();
    notifier = PlayerNotifier(handler);
  });

  tearDown(() async {
    // Riverpod owns and disposes `notifier` itself once the ProviderScope
    // that overrides playerProvider with it is unmounted between tests.
    await handler.close();
  });

  Future<void> pump(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
      ),
    );
  }

  testWidgets('ne rend rien sans piste courante', (tester) async {
    await pump(tester);

    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.text('Track'), findsNothing);
  });

  testWidgets('affiche le titre et l\'artiste de la piste courante', (tester) async {
    await notifier.play(_track(title: 'Around the World', artist: 'Daft Punk'));
    await pump(tester);

    expect(find.text('Around the World'), findsOneWidget);
    expect(find.text('Daft Punk'), findsOneWidget);
  });

  testWidgets('affiche "Unknown artist" quand l\'artiste est vide', (tester) async {
    await notifier.play(_track(artist: ''));
    await pump(tester);

    expect(find.text('Unknown artist'), findsOneWidget);
  });

  testWidgets('le bouton play/pause suit l\'etat de lecture', (tester) async {
    await notifier.play(_track());
    await pump(tester);

    expect(find.byIcon(Icons.pause_circle_filled), findsNothing);
    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);

    handler.playing.add(true);
    await tester.pump();

    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
  });

  testWidgets('tap sur le bouton play/pause delegue au notifier', (tester) async {
    await notifier.play(_track());
    await pump(tester);

    handler.playing.add(true);
    await tester.pump();
    handler.calls.clear();

    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pump();

    expect(handler.calls, contains('pause'));
  });

  testWidgets('tap sur le lecteur mini navigue vers /player', (tester) async {
    await notifier.play(_track());

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const MiniPlayer()),
        GoRoute(path: '/player', builder: (context, state) => const Text('Player screen')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWith((ref) => notifier)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.byType(MiniPlayer));
    await tester.pumpAndSettle();

    expect(find.text('Player screen'), findsOneWidget);
  });
}
