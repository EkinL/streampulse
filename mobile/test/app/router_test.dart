import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide StreamNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/app/router.dart';
import 'package:streampulse/app/theme.dart';
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
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
import 'package:streampulse/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:streampulse/features/music/presentation/providers/music_provider.dart';
import 'package:streampulse/features/streams/data/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/stream_provider.dart';

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
  _FakeAuthNotifier(AuthState initial)
      : super(
          AuthRepository(Dio()),
          AuthLocalSource(SecureStorageService(store: _NullStore())),
        ) {
    state = initial;
  }
}

class _FakeHandler extends Fake implements StreamPulseAudioHandler {
  @override
  VoidCallback? onSkipToNext;
  @override
  VoidCallback? onSkipToPrevious;
  @override
  VoidCallback? onLiveStop;
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

UserModel _user({String role = 'listener'}) => UserModel(
      id: 'u1',
      email: 'alice@example.com',
      username: 'alice',
      role: role,
    );

Future<void> _pump(
  WidgetTester tester, {
  required AuthState authState,
  required String initialLocation,
}) async {
  final streamRepository = _MockStreamRepository();
  final favoritesRepository = _MockFavoritesRepository();
  final musicRepository = _MockMusicRepository();
  final dio = _MockDio();
  when(() => streamRepository.listStreams()).thenAnswer((_) async => []);
  when(() => favoritesRepository.listFavorites()).thenAnswer((_) async => []);
  when(() => musicRepository.listMusic()).thenAnswer((_) async => []);
  when(() => dio.get(ApiEndpoints.musicFavoriteIds)).thenAnswer(
    (_) async => Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {
        'data': {'ids': <String>[]},
      },
    ),
  );

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(authState)),
      audioHandlerProvider.overrideWithValue(_FakeHandler()),
      streamListProvider.overrideWith((ref) => StreamNotifier(streamRepository)),
      favoritesProvider.overrideWith((ref) => FavoritesNotifier(favoritesRepository)),
      musicListProvider.overrideWith((ref) => MusicNotifier(musicRepository)),
      musicFavoritesProvider.overrideWith((ref) => MusicFavoritesNotifier(dio)),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(routerProvider);
  router.go(initialLocation);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('route publique /privacy accessible sans authentification', (tester) async {
    await _pump(tester, authState: const AuthUnauthenticated(), initialLocation: '/privacy');

    expect(find.text('Politique de confidentialité'), findsOneWidget);
  });

  testWidgets('route protegee sans session redirige vers /login', (tester) async {
    await _pump(tester, authState: const AuthUnauthenticated(), initialLocation: '/streams');

    expect(find.text('StreamPulse'), findsOneWidget);
  });

  testWidgets('authentifie sur /login est redirige vers /streams', (tester) async {
    await _pump(tester, authState: AuthAuthenticated(user: _user(), token: 't'), initialLocation: '/login');

    expect(find.byIcon(Icons.radio), findsOneWidget);
  });

  testWidgets('non-admin sur /admin est redirige vers /streams', (tester) async {
    await _pump(
      tester,
      authState: AuthAuthenticated(user: _user(role: 'listener'), token: 't'),
      initialLocation: '/admin',
    );

    expect(find.text('ADMIN'), findsNothing);
    expect(find.byIcon(Icons.radio), findsOneWidget);
  });

  testWidgets('non-diffuseur sur /broadcaster est redirige vers /streams', (tester) async {
    await _pump(
      tester,
      authState: AuthAuthenticated(user: _user(role: 'listener'), token: 't'),
      initialLocation: '/broadcaster',
    );

    expect(find.byIcon(Icons.radio), findsOneWidget);
  });

  testWidgets('route inconnue affiche la page 404', (tester) async {
    await _pump(
      tester,
      authState: AuthAuthenticated(user: _user(), token: 't'),
      initialLocation: '/nope',
    );

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('Go Home'), findsOneWidget);
  });
}
