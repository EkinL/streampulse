import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide StreamNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';
import 'package:streampulse/features/favorites/data/favorites_repository.dart';
import 'package:streampulse/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:streampulse/features/music/data/music_repository.dart';
import 'package:streampulse/features/music/domain/music_model.dart';
import 'package:streampulse/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:streampulse/features/music/presentation/providers/music_provider.dart';
import 'package:streampulse/features/streams/data/stream_repository.dart';
import 'package:streampulse/features/streams/domain/stream_model.dart';
import 'package:streampulse/features/streams/presentation/providers/stream_provider.dart';
import 'package:streampulse/features/streams/presentation/screens/streams_list_screen.dart';
import 'package:dio/dio.dart';
import 'package:streampulse/app/theme.dart';

class _MockStreamRepository extends Mock implements StreamRepository {}

class _MockFavoritesRepository extends Mock implements FavoritesRepository {}

class _MockMusicRepository extends Mock implements MusicRepository {}

class _MockDio extends Mock implements Dio {}

class _NullStore implements TokenStore {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(String role)
      : super(
          AuthRepository(Dio()),
          AuthLocalSource(SecureStorageService(store: _NullStore())),
        ) {
    state = AuthAuthenticated(
      user: UserModel(id: 'u1', email: 'a@example.com', username: 'alice', role: role),
      token: 't',
    );
  }
}

class _FakeHandler extends Fake implements StreamPulseAudioHandler {
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
  Future<void> setVolume(double v) async {}
}

StreamModel _stream(String id, {String title = 'Stream', bool live = true}) => StreamModel(
      id: id,
      title: title,
      description: '',
      ownerId: 'owner',
      status: live ? 'live' : 'ended',
      listenerCount: 5,
      format: 'mp3',
      createdAt: DateTime(2026),
    );

MusicModel _music(String id, {String title = 'Track'}) => MusicModel(
      id: id,
      title: title,
      artist: 'Artist',
      album: '',
      duration: 90,
      url: 'https://cdn/$id.mp3',
      uploadedBy: 'u1',
      createdAt: DateTime(2026),
    );

Future<void> _pump(
  WidgetTester tester, {
  required _MockStreamRepository streamRepository,
  required _MockFavoritesRepository favoritesRepository,
  required _MockMusicRepository musicRepository,
  String role = 'listener',
}) async {
  final dio = _MockDio();
  when(() => dio.get(ApiEndpoints.musicFavoriteIds)).thenAnswer(
    (_) async => Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {
        'data': {'ids': <String>[]},
      },
    ),
  );
  final router = GoRouter(
    initialLocation: '/streams',
    routes: [
      GoRoute(path: '/streams', builder: (c, s) => const StreamsListScreen()),
      GoRoute(
        path: '/streams/:id',
        builder: (c, s) => Text('Stream ${s.pathParameters['id']}'),
      ),
      GoRoute(path: '/search', builder: (c, s) => const Text('Search screen')),
      GoRoute(path: '/broadcaster', builder: (c, s) => const Text('Broadcaster screen')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(_FakeHandler()),
        authProvider.overrideWith((ref) => _FakeAuthNotifier(role)),
        streamListProvider.overrideWith((ref) => StreamNotifier(streamRepository)),
        favoritesProvider.overrideWith((ref) => FavoritesNotifier(favoritesRepository, enabled: true)),
        musicListProvider.overrideWith((ref) => MusicNotifier(musicRepository)),
        musicFavoritesProvider.overrideWith((ref) => MusicFavoritesNotifier(dio)),
      ],
      child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockStreamRepository streamRepository;
  late _MockFavoritesRepository favoritesRepository;
  late _MockMusicRepository musicRepository;

  setUp(() {
    streamRepository = _MockStreamRepository();
    favoritesRepository = _MockFavoritesRepository();
    musicRepository = _MockMusicRepository();
    when(() => musicRepository.listMusic()).thenAnswer((_) async => []);
    when(() => favoritesRepository.listFavorites()).thenAnswer((_) async => []);
  });

  testWidgets('affiche un etat vide sans stream', (tester) async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => []);

    await _pump(
      tester,
      streamRepository: streamRepository,
      favoritesRepository: favoritesRepository,
      musicRepository: musicRepository,
    );
    await tester.pump();

    expect(find.text('No streams available'), findsOneWidget);
  });

  testWidgets('affiche une erreur de chargement', (tester) async {
    when(() => streamRepository.listStreams()).thenThrow(const ApiException(message: 'boom'));

    await _pump(
      tester,
      streamRepository: streamRepository,
      favoritesRepository: favoritesRepository,
      musicRepository: musicRepository,
    );
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('affiche le hero card et la liste des streams', (tester) async {
    when(() => streamRepository.listStreams())
        .thenAnswer((_) async => [_stream('s1', title: 'Live show', live: true)]);

    await _pump(
      tester,
      streamRepository: streamRepository,
      favoritesRepository: favoritesRepository,
      musicRepository: musicRepository,
    );
    await tester.pump();

    expect(find.text('Live show'), findsWidgets);
    expect(find.text('Flux actifs'), findsOneWidget);
  });

  testWidgets('affiche la musique recente quand disponible', (tester) async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1')]);
    when(() => musicRepository.listMusic()).thenAnswer((_) async => [_music('m1', title: 'A track')]);

    await _pump(
      tester,
      streamRepository: streamRepository,
      favoritesRepository: favoritesRepository,
      musicRepository: musicRepository,
    );
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('A track'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );

    expect(find.text('Recent Music'), findsOneWidget);
    expect(find.text('A track'), findsOneWidget);
  });

  testWidgets('aucun bouton broadcast pour un simple auditeur', (tester) async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1')]);

    await _pump(
      tester,
      streamRepository: streamRepository,
      favoritesRepository: favoritesRepository,
      musicRepository: musicRepository,
      role: 'listener',
    );
    await tester.pump();

    expect(find.text('Broadcast'), findsNothing);
  });

  testWidgets('le bouton broadcast navigue vers /broadcaster pour un diffuseur', (tester) async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1')]);

    await _pump(
      tester,
      streamRepository: streamRepository,
      favoritesRepository: favoritesRepository,
      musicRepository: musicRepository,
      role: 'broadcaster',
    );
    await tester.pump();

    await tester.tap(find.text('Broadcast'));
    await tester.pumpAndSettle();

    expect(find.text('Broadcaster screen'), findsOneWidget);
  });

  testWidgets('tap sur la loupe navigue vers /search', (tester) async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1')]);

    await _pump(
      tester,
      streamRepository: streamRepository,
      favoritesRepository: favoritesRepository,
      musicRepository: musicRepository,
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('Search screen'), findsOneWidget);
  });

  testWidgets('tap sur un stream navigue vers son detail', (tester) async {
    when(() => streamRepository.listStreams())
        .thenAnswer((_) async => [_stream('s1', title: 'Only stream')]);

    await _pump(
      tester,
      streamRepository: streamRepository,
      favoritesRepository: favoritesRepository,
      musicRepository: musicRepository,
    );
    await tester.pump();

    await tester.tap(find.text('Only stream').first);
    await tester.pumpAndSettle();

    expect(find.text('Stream s1'), findsOneWidget);
  });

  testWidgets('editer un stream possede par l\'utilisateur courant', (tester) async {
    final stream = StreamModel(
      id: 's1',
      title: 'My stream',
      description: 'Desc',
      ownerId: 'u1',
      // Statut "ended" : un stream live anime en continu AudioWaveform, ce
      // qui empeche pumpAndSettle de se stabiliser une fois la dialog ouverte.
      status: 'ended',
      listenerCount: 0,
      format: 'mp3',
      createdAt: DateTime(2026),
    );
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [stream]);
    when(() => streamRepository.updateStream(
          id: 's1',
          title: 'Renamed',
          description: 'Desc',
        )).thenAnswer((_) async => stream);

    await _pump(
      tester,
      streamRepository: streamRepository,
      favoritesRepository: favoritesRepository,
      musicRepository: musicRepository,
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    final titleField = find.widgetWithText(TextField, 'My stream');
    await tester.enterText(titleField, 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => streamRepository.updateStream(id: 's1', title: 'Renamed', description: 'Desc')).called(1);
    expect(find.text('Stream updated'), findsOneWidget);
  });
}
