import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide StreamNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/streams/data/stream_repository.dart';
import 'package:streampulse/features/streams/domain/stream_model.dart';
import 'package:streampulse/features/streams/presentation/providers/live_stream_provider.dart';
import 'package:streampulse/features/streams/presentation/providers/stream_provider.dart';
import 'package:streampulse/shared/widgets/live_mini_player.dart';
import 'package:streampulse/app/theme.dart';

class _MockStreamRepository extends Mock implements StreamRepository {}

class _NullStore implements TokenStore {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _FakeLiveStreamNotifier extends LiveStreamNotifier {
  _FakeLiveStreamNotifier() : super(SecureStorageService(store: _NullStore()));

  void setTestState(LiveStreamState newState) => state = newState;
}

StreamModel _stream(String id, {int listenerCount = 5}) => StreamModel(
      id: id,
      title: 'Stream $id',
      description: '',
      ownerId: 'u1',
      status: 'live',
      listenerCount: listenerCount,
      format: 'mp3',
      createdAt: DateTime(2026),
    );

Future<_FakeLiveStreamNotifier> _pump(
  WidgetTester tester, {
  required _MockStreamRepository streamRepository,
}) async {
  final liveNotifier = _FakeLiveStreamNotifier();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (c, s) => const Scaffold(body: LiveMiniPlayer())),
      GoRoute(
        path: '/streams/:id',
        builder: (c, s) => Text('Stream ${s.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        liveStreamProvider.overrideWith((ref) => liveNotifier),
        streamListProvider.overrideWith((ref) => StreamNotifier(streamRepository)),
      ],
      child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
    ),
  );
  await tester.pump();
  return liveNotifier;
}

void main() {
  late _MockStreamRepository streamRepository;

  setUp(() {
    streamRepository = _MockStreamRepository();
    when(() => streamRepository.listStreams()).thenAnswer((_) async => []);
  });

  testWidgets('ne rend rien quand aucun flux n\'est connecte', (tester) async {
    await _pump(tester, streamRepository: streamRepository);

    expect(find.byType(LiveMiniPlayer), findsOneWidget);
    expect(find.byIcon(Icons.podcasts), findsNothing);
  });

  testWidgets('affiche le titre et le nombre d\'auditeurs quand connecte', (tester) async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1', listenerCount: 42)]);

    final liveNotifier = await _pump(tester, streamRepository: streamRepository);
    liveNotifier.setTestState(
      const LiveStreamState(streamId: 's1', title: 'Night Show', isConnected: true),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Night Show'), findsOneWidget);
    expect(find.textContaining('42'), findsOneWidget);
  });

  testWidgets('affiche "Direct" quand le titre est absent et le nombre d\'auditeurs inconnu', (tester) async {
    final liveNotifier = await _pump(tester, streamRepository: streamRepository);
    liveNotifier.setTestState(
      const LiveStreamState(streamId: 'unknown', isConnected: true),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Direct'), findsOneWidget);
    expect(find.text('En direct'), findsOneWidget);
  });

  testWidgets('tap sur la barre navigue vers le detail du flux', (tester) async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1')]);

    final liveNotifier = await _pump(tester, streamRepository: streamRepository);
    liveNotifier.setTestState(
      const LiveStreamState(streamId: 's1', title: 'Night Show', isConnected: true),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Night Show'));
    await tester.pumpAndSettle();

    expect(find.text('Stream s1'), findsOneWidget);
  });

  testWidgets('le bouton pause appelle disconnect', (tester) async {
    final liveNotifier = await _pump(tester, streamRepository: streamRepository);
    liveNotifier.setTestState(
      const LiveStreamState(streamId: 's1', title: 'Night Show', isConnected: true),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.pause_circle_filled));
    await tester.pump();

    expect(liveNotifier.state.isConnected, isFalse);
  });
}
