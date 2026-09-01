import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/music/data/music_repository.dart';
import 'package:streampulse/features/music/domain/music_model.dart';
import 'package:streampulse/features/playlists/data/playlist_repository.dart';
import 'package:streampulse/features/playlists/domain/playlist_model.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_provider.dart';
import 'package:streampulse/features/playlists/presentation/screens/playlist_detail_screen.dart';
import 'package:streampulse/app/theme.dart';

class _MockPlaylistRepository extends Mock implements PlaylistRepository {}

class _MockMusicRepository extends Mock implements MusicRepository {}

class _FakeHandler extends Fake implements StreamPulseAudioHandler {
  final calls = <String>[];

  @override
  VoidCallback? onSkipToNext;
  @override
  VoidCallback? onSkipToPrevious;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override
  Stream<double> get volumeStream => const Stream.empty();

  @override
  Future<Duration?> loadTrack(MediaItem item, String url) async {
    calls.add('load:$url');
    return null;
  }

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> setVolume(double v) async {}
}

TrackModel _trackModel(String id, {String title = 'Track', int position = 0}) => TrackModel(
      id: id,
      title: title,
      url: 'https://cdn/$id.mp3',
      duration: 90,
      position: position,
    );

PlaylistModel _playlist({
  String id = 'p1',
  String name = 'Chill mix',
  bool isPublic = false,
  List<TrackModel> tracks = const [],
}) =>
    PlaylistModel(
      id: id,
      name: name,
      ownerId: 'u1',
      isPublic: isPublic,
      tracks: tracks,
      trackCount: tracks.length,
      createdAt: DateTime(2026),
    );

Future<_FakeHandler> _pump(
  WidgetTester tester, {
  required _MockPlaylistRepository playlistRepository,
  required _MockMusicRepository musicRepository,
}) async {
  final handler = _FakeHandler();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        playlistListProvider.overrideWith((ref) => PlaylistNotifier(playlistRepository)),
        playlistDetailProvider.overrideWith((ref, id) => playlistRepository.getPlaylist(id)),
      ],
      child: MaterialApp(theme: AppTheme.darkTheme, home: const PlaylistDetailScreen(playlistId: 'p1')),
    ),
  );
  await tester.pump();
  return handler;
}

void main() {
  late _MockPlaylistRepository playlistRepository;
  late _MockMusicRepository musicRepository;

  setUp(() {
    playlistRepository = _MockPlaylistRepository();
    musicRepository = _MockMusicRepository();
    when(() => playlistRepository.listPlaylists()).thenAnswer((_) async => []);
  });

  testWidgets('affiche un indicateur de chargement puis les details', (tester) async {
    final completer = Completer<PlaylistModel>();
    when(() => playlistRepository.getPlaylist('p1')).thenAnswer((_) => completer.future);

    await _pump(tester, playlistRepository: playlistRepository, musicRepository: musicRepository);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_playlist(name: 'Chill mix', isPublic: true));
    await tester.pump();

    expect(find.text('Chill mix'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('0 titres'), findsOneWidget);
  });

  testWidgets('affiche une erreur et permet de reessayer', (tester) async {
    when(() => playlistRepository.getPlaylist('p1')).thenThrow(const ApiException(message: 'boom'));

    await _pump(tester, playlistRepository: playlistRepository, musicRepository: musicRepository);
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);

    when(() => playlistRepository.getPlaylist('p1')).thenAnswer((_) async => _playlist());
    await tester.tap(find.text('Try Again'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Chill mix'), findsOneWidget);
  });

  testWidgets('affiche un etat vide sans piste et pas de bouton Play All', (tester) async {
    when(() => playlistRepository.getPlaylist('p1')).thenAnswer((_) async => _playlist());

    await _pump(tester, playlistRepository: playlistRepository, musicRepository: musicRepository);
    await tester.pump();

    expect(find.text('Aucun titre pour l\'instant'), findsOneWidget);
    expect(find.text('Tout écouter'), findsNothing);
  });

  testWidgets('liste les pistes et Play All lance la lecture depuis le debut', (tester) async {
    when(() => playlistRepository.getPlaylist('p1')).thenAnswer(
      (_) async => _playlist(tracks: [_trackModel('t1', title: 'Song A'), _trackModel('t2', title: 'Song B', position: 1)]),
    );

    final handler = await _pump(tester, playlistRepository: playlistRepository, musicRepository: musicRepository);
    await tester.pump();

    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Song B'), findsOneWidget);
    expect(find.text('2 titres'), findsOneWidget);

    await tester.tap(find.text('Tout écouter'));
    await tester.pump();

    expect(handler.calls, contains('load:https://cdn/t1.mp3'));
  });

  testWidgets('tap sur une piste la joue a partir de son index', (tester) async {
    when(() => playlistRepository.getPlaylist('p1')).thenAnswer(
      (_) async => _playlist(tracks: [_trackModel('t1', title: 'Song A'), _trackModel('t2', title: 'Song B', position: 1)]),
    );

    final handler = await _pump(tester, playlistRepository: playlistRepository, musicRepository: musicRepository);
    await tester.pump();

    await tester.tap(find.text('Song B'));
    await tester.pump();

    expect(handler.calls, contains('load:https://cdn/t2.mp3'));
  });

  testWidgets('retirer une piste appelle removeTrack', (tester) async {
    when(() => playlistRepository.getPlaylist('p1'))
        .thenAnswer((_) async => _playlist(tracks: [_trackModel('t1', title: 'Song A')]));
    when(() => playlistRepository.removeTrack(playlistId: 'p1', trackId: 't1')).thenAnswer((_) async {});

    await _pump(tester, playlistRepository: playlistRepository, musicRepository: musicRepository);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump();

    verify(() => playlistRepository.removeTrack(playlistId: 'p1', trackId: 't1')).called(1);
    expect(find.text('Titre retiré'), findsOneWidget);
  });

  testWidgets('ouvre la feuille d\'ajout et recherche un morceau', (tester) async {
    when(() => playlistRepository.getPlaylist('p1')).thenAnswer((_) async => _playlist());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(_FakeHandler()),
          playlistListProvider.overrideWith((ref) => PlaylistNotifier(playlistRepository)),
          playlistDetailProvider.overrideWith((ref, id) => playlistRepository.getPlaylist(id)),
          musicRepositoryProvider.overrideWithValue(musicRepository),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const PlaylistDetailScreen(playlistId: 'p1')),
      ),
    );
    await tester.pump();

    when(() => musicRepository.searchMusic('song')).thenAnswer(
      (_) async => [
        MusicModel(
          id: 'm1',
          title: 'Found song',
          artist: 'Artist',
          album: '',
          duration: 60,
          url: 'u',
          uploadedBy: 'u1',
          createdAt: DateTime(2026),
        ),
      ],
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un titre'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'song');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Found song'), findsOneWidget);

    when(() => playlistRepository.addTrack(
          playlistId: 'p1',
          title: 'Found song',
          url: 'u',
          duration: 60,
        )).thenAnswer((_) async {});

    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pumpAndSettle();

    verify(() => playlistRepository.addTrack(
          playlistId: 'p1',
          title: 'Found song',
          url: 'u',
          duration: 60,
        )).called(1);
    expect(find.text('Titre ajouté'), findsOneWidget);
  });
}
