import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide StreamNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';
import 'package:streampulse/features/favorites/data/favorites_repository.dart';
import 'package:streampulse/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:streampulse/features/streams/data/stream_repository.dart';
import 'package:streampulse/features/streams/domain/stream_model.dart';
import 'package:streampulse/features/streams/presentation/providers/stream_provider.dart';
import 'package:streampulse/features/streams/presentation/screens/stream_detail_screen.dart';
import 'package:streampulse/app/theme.dart';

class _MockStreamRepository extends Mock implements StreamRepository {}

class _MockFavoritesRepository extends Mock implements FavoritesRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthLocalSource extends Mock implements AuthLocalSource {}

/// Session connectée : l'écran garde les actions (favoris, chat) pour les
/// visiteurs sans compte, ces tests couvrent le parcours connecté.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier() : super(_MockAuthRepository(), _MockAuthLocalSource()) {
    state = const AuthAuthenticated(
      user: UserModel(id: 'u1', email: 'a@a.fr', username: 'alice', role: 'user'),
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

StreamModel _stream({
  String id = 's1',
  String title = 'Night Show',
  String description = '',
  String status = 'live',
  int listenerCount = 12,
  String format = 'mp3',
}) =>
    StreamModel(
      id: id,
      title: title,
      description: description,
      ownerId: 'u1',
      status: status,
      listenerCount: listenerCount,
      format: format,
      createdAt: DateTime(2026, 1, 15, 10),
    );

Future<void> _pump(
  WidgetTester tester, {
  required _MockStreamRepository streamRepository,
  required _MockFavoritesRepository favoritesRepository,
}) async {
  // StreamDetailScreen arme un Timer.periodic (auto-refresh) annule dans
  // dispose() : on demonte l'arbre en fin de test pour qu'il ne reste pas
  // en attente et fasse echouer l'assertion !timersPending du binding.
  addTearDown(() => tester.pumpWidget(const SizedBox()));

  tester.view.physicalSize = const Size(500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(_FakeHandler()),
        authProvider.overrideWith((ref) => _FakeAuthNotifier()),
        streamRepositoryProvider.overrideWithValue(streamRepository),
        streamListProvider.overrideWith((ref) => StreamNotifier(streamRepository)),
        favoritesProvider.overrideWith((ref) => FavoritesNotifier(favoritesRepository, enabled: true)),
      ],
      child: MaterialApp(theme: AppTheme.darkTheme, home: const StreamDetailScreen(streamId: 's1')),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockStreamRepository streamRepository;
  late _MockFavoritesRepository favoritesRepository;

  setUp(() {
    streamRepository = _MockStreamRepository();
    favoritesRepository = _MockFavoritesRepository();
    when(() => streamRepository.listStreams()).thenAnswer((_) async => []);
    when(() => favoritesRepository.listFavorites()).thenAnswer((_) async => []);
  });

  testWidgets('affiche un indicateur de chargement puis les details du stream', (tester) async {
    final completer = Completer<StreamModel>();
    when(() => streamRepository.getStream('s1')).thenAnswer((_) => completer.future);

    await _pump(tester, streamRepository: streamRepository, favoritesRepository: favoritesRepository);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_stream(title: 'Night Show', description: 'Late night mix'));
    await tester.pump();

    expect(find.text('Night Show'), findsWidgets);
    expect(find.text('Late night mix'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('MP3'), findsOneWidget);
  });

  testWidgets('affiche une erreur et permet de reessayer', (tester) async {
    when(() => streamRepository.getStream('s1')).thenThrow(const ApiException(message: 'boom'));

    await _pump(tester, streamRepository: streamRepository, favoritesRepository: favoritesRepository);
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);

    when(() => streamRepository.getStream('s1')).thenAnswer((_) async => _stream());
    await tester.tap(find.text('Try Again'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Night Show'), findsWidgets);
  });

  testWidgets('n\'affiche pas de section description quand elle est vide', (tester) async {
    when(() => streamRepository.getStream('s1')).thenAnswer((_) async => _stream(description: ''));

    await _pump(tester, streamRepository: streamRepository, favoritesRepository: favoritesRepository);
    await tester.pump();

    expect(find.text('Description'), findsNothing);
  });

  testWidgets('le bouton favori appelle toggleFavorite et affiche une confirmation', (tester) async {
    when(() => streamRepository.getStream('s1')).thenAnswer((_) async => _stream());
    when(() => favoritesRepository.addFavorite('s1')).thenAnswer((_) async {});

    await _pump(tester, streamRepository: streamRepository, favoritesRepository: favoritesRepository);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    verify(() => favoritesRepository.addFavorite('s1')).called(1);
    expect(find.text('Added to favorites'), findsOneWidget);
  });

  testWidgets('affiche le badge HORS LIGNE pour un stream termine', (tester) async {
    when(() => streamRepository.getStream('s1')).thenAnswer((_) async => _stream(status: 'ended'));

    await _pump(tester, streamRepository: streamRepository, favoritesRepository: favoritesRepository);
    await tester.pump();

    expect(find.text('HORS LIGNE'), findsOneWidget);
  });
}
