import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/core/network/api_client.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:streampulse/features/music/presentation/screens/search_screen.dart';

class _MockDio extends Mock implements Dio {}

class _FakeHandler extends Fake implements StreamPulseAudioHandler {
  final loaded = <String>[];

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
    loaded.add(url);
    return null;
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> setVolume(double v) async {}
}

Response<T> _response<T>(T data) => Response<T>(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: data,
    );

Map<String, dynamic> _streamJson(String id, {String title = 'Stream'}) => {
      'id': id,
      'title': title,
      'owner_id': 'u1',
      'status': 'live',
      'created_at': '2026-01-15T10:00:00Z',
    };

Map<String, dynamic> _musicJson(String id, {String title = 'Track'}) => {
      'id': id,
      'title': title,
      'artist': 'Artist',
      'url': 'https://cdn/$id.mp3',
      'uploaded_by': 'u1',
      'created_at': '2026-01-15T10:00:00Z',
    };

Future<_FakeHandler> _pump(WidgetTester tester, {required _MockDio dio}) async {
  final handler = _FakeHandler();
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(path: '/search', builder: (c, s) => const SearchScreen()),
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
        dioProvider.overrideWithValue(dio),
        audioHandlerProvider.overrideWithValue(handler),
        musicFavoritesProvider.overrideWith((ref) => MusicFavoritesNotifier(dio)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  return handler;
}

void main() {
  late _MockDio dio;

  setUp(() {
    dio = _MockDio();
  });

  testWidgets('affiche l\'invite initiale avant toute recherche', (tester) async {
    await _pump(tester, dio: dio);

    expect(find.text('Search for streams and music'), findsOneWidget);
  });

  testWidgets('recherche apres debounce et affiche streams + musique', (tester) async {
    when(() => dio.get(
          ApiEndpoints.globalSearch,
          queryParameters: {'q': 'daft'},
        )).thenAnswer((_) async => _response({
          'data': {
            'streams': [_streamJson('s1', title: 'Live show')],
            'music': [_musicJson('m1', title: 'Harder Better')],
          },
        }));

    await _pump(tester, dio: dio);

    await tester.enterText(find.byType(TextField), 'daft');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Streams'), findsOneWidget);
    expect(find.text('Live show'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Harder Better'), findsOneWidget);
  });

  testWidgets('aucun resultat affiche un etat vide dedie', (tester) async {
    when(() => dio.get(
          ApiEndpoints.globalSearch,
          queryParameters: {'q': 'zzz'},
        )).thenAnswer((_) async => _response({'data': <String, dynamic>{}}));

    await _pump(tester, dio: dio);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('No results found'), findsOneWidget);
  });

  testWidgets('vider la requete revient a l\'invite initiale', (tester) async {
    when(() => dio.get(
          ApiEndpoints.globalSearch,
          queryParameters: {'q': 'daft'},
        )).thenAnswer((_) async => _response({'data': <String, dynamic>{}}));

    await _pump(tester, dio: dio);
    await tester.enterText(find.byType(TextField), 'daft');
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('No results found'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Search for streams and music'), findsOneWidget);
  });

  testWidgets('tap sur un stream navigue vers son detail', (tester) async {
    when(() => dio.get(
          ApiEndpoints.globalSearch,
          queryParameters: {'q': 'live'},
        )).thenAnswer((_) async => _response({
          'data': {
            'streams': [_streamJson('s1', title: 'Live show')],
            'music': <dynamic>[],
          },
        }));

    await _pump(tester, dio: dio);
    await tester.enterText(find.byType(TextField), 'live');
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.text('Live show'));
    await tester.pumpAndSettle();

    expect(find.text('Stream s1'), findsOneWidget);
  });

  testWidgets('tap sur un morceau le joue via le lecteur', (tester) async {
    when(() => dio.get(
          ApiEndpoints.globalSearch,
          queryParameters: {'q': 'track'},
        )).thenAnswer((_) async => _response({
          'data': {
            'streams': <dynamic>[],
            'music': [_musicJson('m1', title: 'Around the World')],
          },
        }));

    final handler = await _pump(tester, dio: dio);
    await tester.enterText(find.byType(TextField), 'track');
    await tester.pump(const Duration(milliseconds: 350));

    await tester.tap(find.byIcon(Icons.play_circle_filled));
    await tester.pump();

    expect(handler.loaded, isNotEmpty);
  });

  testWidgets('la fleche retour ferme l\'ecran', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final dio = _MockDio();
    final handler = _FakeHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          audioHandlerProvider.overrideWithValue(handler),
          musicFavoritesProvider.overrideWith((ref) => MusicFavoritesNotifier(dio)),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
              ),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsNothing);
  });
}
