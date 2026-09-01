import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/features/music/domain/music_model.dart';
import 'package:streampulse/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:streampulse/features/music/presentation/screens/music_player_screen.dart';
import 'package:streampulse/features/playlists/data/playlist_repository.dart';
import 'package:streampulse/features/playlists/domain/playlist_model.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_provider.dart';
import 'package:streampulse/shared/providers/player_provider.dart';
import 'package:streampulse/app/theme.dart';

class _MockDio extends Mock implements Dio {}

class _MockPlaylistRepository extends Mock implements PlaylistRepository {}

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

MusicModel _track({String id = 'm1', String title = 'Around the World', String artist = 'Daft Punk'}) =>
    MusicModel(
      id: id,
      title: title,
      artist: artist,
      album: '',
      duration: 125,
      url: '/music/$id/file',
      uploadedBy: 'u1',
      createdAt: DateTime(2026),
    );

PlaylistModel _playlist(String id, {String name = 'Chill'}) => PlaylistModel(
      id: id,
      name: name,
      ownerId: 'u1',
      isPublic: false,
      tracks: const [],
      trackCount: 0,
      createdAt: DateTime(2026),
    );

void main() {
  late _FakeHandler handler;
  late PlayerNotifier playerNotifier;
  late _MockDio dio;
  late _MockPlaylistRepository playlistRepository;

  setUp(() {
    handler = _FakeHandler();
    playerNotifier = PlayerNotifier(handler);
    dio = _MockDio();
    playlistRepository = _MockPlaylistRepository();
  });

  tearDown(() async {
    await handler.close();
  });

  Future<void> pump(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => playerNotifier),
          musicFavoritesProvider.overrideWith((ref) => MusicFavoritesNotifier(dio)),
          playlistListProvider.overrideWith((ref) => PlaylistNotifier(playlistRepository)),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const MusicPlayerScreen()),
      ),
    );
  }

  testWidgets('affiche un etat vide sans piste courante', (tester) async {
    await pump(tester);

    expect(find.text('No track playing'), findsOneWidget);
  });

  testWidgets('affiche le titre et l\'artiste de la piste en cours', (tester) async {
    when(() => playlistRepository.listPlaylists()).thenAnswer((_) async => []);
    await playerNotifier.play(_track());
    await pump(tester);

    expect(find.text('Around the World'), findsOneWidget);
    expect(find.text('Daft Punk'), findsOneWidget);
  });

  testWidgets('le bouton favori bascule l\'etat favori du morceau', (tester) async {
    when(() => playlistRepository.listPlaylists()).thenAnswer((_) async => []);
    await playerNotifier.play(_track());
    when(() => dio.post(any())).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
        ));
    await pump(tester);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('play/pause, next et previous delegue au notifier', (tester) async {
    when(() => playlistRepository.listPlaylists()).thenAnswer((_) async => []);
    await playerNotifier.play(_track());
    await pump(tester);
    handler.calls.clear();

    await tester.tap(find.byIcon(Icons.play_circle_filled));
    await tester.pump();
    expect(handler.calls, contains('play'));

    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.pump();
    expect(handler.calls, contains('seek'));
  });

  testWidgets('ouvre la feuille "Add to Playlist" et liste les playlists existantes', (tester) async {
    when(() => playlistRepository.listPlaylists())
        .thenAnswer((_) async => [_playlist('p1', name: 'Chill mix')]);
    await playerNotifier.play(_track());
    await pump(tester);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.playlist_add));
    await tester.pumpAndSettle();

    expect(find.text('Add to Playlist'), findsOneWidget);
    expect(find.text('Chill mix'), findsOneWidget);
  });

  testWidgets('ajouter la piste a une playlist existante', (tester) async {
    when(() => playlistRepository.listPlaylists())
        .thenAnswer((_) async => [_playlist('p1', name: 'Chill mix')]);
    await playerNotifier.play(_track());
    await pump(tester);
    await tester.pump();

    when(() => playlistRepository.addTrack(
          playlistId: 'p1',
          title: 'Around the World',
          url: '/music/m1/file',
          duration: 125,
        )).thenAnswer((_) async {});

    await tester.tap(find.byIcon(Icons.playlist_add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chill mix'));
    await tester.pumpAndSettle();

    verify(() => playlistRepository.addTrack(
          playlistId: 'p1',
          title: 'Around the World',
          url: '/music/m1/file',
          duration: 125,
        )).called(1);
    expect(find.textContaining('Added to'), findsOneWidget);
  });

  testWidgets('creer une nouvelle playlist et y ajouter la piste', (tester) async {
    when(() => playlistRepository.listPlaylists()).thenAnswer((_) async => []);
    await playerNotifier.play(_track());
    await pump(tester);
    await tester.pump();

    when(() => playlistRepository.createPlaylist(name: 'New list', isPublic: false))
        .thenAnswer((_) async => _playlist('p2', name: 'New list'));
    when(() => playlistRepository.addTrack(
          playlistId: 'p2',
          title: 'Around the World',
          url: '/music/m1/file',
          duration: 125,
        )).thenAnswer((_) async {});
    // Fetched again after create() to resolve the new playlist's id.
    when(() => playlistRepository.listPlaylists()).thenAnswer((_) async => [_playlist('p2', name: 'New list')]);

    await tester.tap(find.byIcon(Icons.playlist_add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create New Playlist'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'New list');
    await tester.tap(find.text('Create & Add'));
    await tester.pumpAndSettle();

    verify(() => playlistRepository.addTrack(
          playlistId: 'p2',
          title: 'Around the World',
          url: '/music/m1/file',
          duration: 125,
        )).called(1);
  });

  testWidgets('deplacer le slider de progression declenche seekTo', (tester) async {
    when(() => playlistRepository.listPlaylists()).thenAnswer((_) async => []);
    await playerNotifier.play(_track());
    await pump(tester);
    await tester.pump();

    handler.duration.add(const Duration(minutes: 2));
    await tester.pump();
    handler.calls.clear();

    await tester.drag(find.byType(Slider).first, const Offset(50, 0));
    await tester.pump();

    expect(handler.calls, contains('seek'));
  });
}
