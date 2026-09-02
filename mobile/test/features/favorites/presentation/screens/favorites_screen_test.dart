import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/favorites/data/favorites_repository.dart';
import 'package:streampulse/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:streampulse/features/favorites/presentation/screens/favorites_screen.dart';
import 'package:streampulse/features/streams/domain/stream_model.dart';
import 'package:streampulse/app/theme.dart';

class _MockFavoritesRepository extends Mock implements FavoritesRepository {}

StreamModel _stream(String id, {String title = 'Stream'}) => StreamModel(
      id: id,
      title: title,
      description: '',
      ownerId: 'u1',
      status: 'live',
      listenerCount: 0,
      format: 'mp3',
      createdAt: DateTime(2026),
    );

Future<void> _pump(
  WidgetTester tester, {
  required _MockFavoritesRepository repository,
}) async {
  final router = GoRouter(
    initialLocation: '/favorites',
    routes: [
      GoRoute(path: '/favorites', builder: (c, s) => const FavoritesScreen()),
      GoRoute(
        path: '/streams/:id',
        builder: (c, s) => Text('Stream ${s.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [favoritesProvider.overrideWith((ref) => FavoritesNotifier(repository, enabled: true))],
      child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockFavoritesRepository repository;

  setUp(() {
    repository = _MockFavoritesRepository();
  });

  testWidgets('affiche un indicateur de chargement pendant la recuperation', (tester) async {
    final completer = Completer<List<StreamModel>>();
    when(() => repository.listFavorites()).thenAnswer((_) => completer.future);

    await _pump(tester, repository: repository);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete([]);
    await tester.pump();
  });

  testWidgets('affiche un etat vide sans favoris', (tester) async {
    when(() => repository.listFavorites()).thenAnswer((_) async => []);

    await _pump(tester, repository: repository);
    await tester.pump();

    expect(find.text('No favorites yet'), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur et permet de reessayer', (tester) async {
    when(() => repository.listFavorites()).thenThrow(const ApiException(message: 'boom'));

    await _pump(tester, repository: repository);
    await tester.pump();

    expect(find.textContaining('Error: boom'), findsOneWidget);

    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1')]);
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.text('Stream'), findsOneWidget);
  });

  testWidgets('liste les favoris et permet d\'y naviguer', (tester) async {
    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1', title: 'Night Show')]);

    await _pump(tester, repository: repository);
    await tester.pump();

    expect(find.text('Night Show'), findsOneWidget);

    await tester.tap(find.text('Night Show'));
    await tester.pumpAndSettle();

    expect(find.text('Stream s1'), findsOneWidget);
  });

  testWidgets('retirer un favori rafraichit la liste', (tester) async {
    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1')]);
    await _pump(tester, repository: repository);
    await tester.pump();

    when(() => repository.removeFavorite('s1')).thenAnswer((_) async {});
    when(() => repository.listFavorites()).thenAnswer((_) async => []);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pump();
    await tester.pump();

    expect(find.text('No favorites yet'), findsOneWidget);
    expect(find.text('Removed from favorites'), findsOneWidget);
  });

  testWidgets('tirer pour rafraichir relance fetch', (tester) async {
    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1')]);
    await _pump(tester, repository: repository);
    await tester.pump();

    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1'), _stream('s2')]);
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    verify(() => repository.listFavorites()).called(greaterThan(1));
  });
}
