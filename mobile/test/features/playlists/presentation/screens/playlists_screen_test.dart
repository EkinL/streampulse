import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/playlists/data/playlist_repository.dart';
import 'package:streampulse/features/playlists/domain/playlist_model.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_provider.dart';
import 'package:streampulse/features/playlists/presentation/screens/playlists_screen.dart';

class _MockPlaylistRepository extends Mock implements PlaylistRepository {}

PlaylistModel _playlist(String id, {String name = 'Playlist'}) => PlaylistModel(
      id: id,
      name: name,
      ownerId: 'u1',
      isPublic: false,
      tracks: const [],
      createdAt: DateTime(2026),
    );

Future<void> _pump(
  WidgetTester tester, {
  required _MockPlaylistRepository repository,
}) async {
  final router = GoRouter(
    initialLocation: '/playlists',
    routes: [
      GoRoute(path: '/playlists', builder: (c, s) => const PlaylistsScreen()),
      GoRoute(
        path: '/playlists/:id',
        builder: (c, s) => Text('Playlist ${s.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [playlistListProvider.overrideWith((ref) => PlaylistNotifier(repository))],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

void main() {
  late _MockPlaylistRepository repository;

  setUp(() {
    repository = _MockPlaylistRepository();
  });

  testWidgets('affiche un etat vide sans playlist', (tester) async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);

    await _pump(tester, repository: repository);
    await tester.pump();

    expect(find.text('No playlists yet'), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur et permet de reessayer', (tester) async {
    when(() => repository.listPlaylists()).thenThrow(const ApiException(message: 'boom'));

    await _pump(tester, repository: repository);
    await tester.pump();

    expect(find.textContaining('Error: boom'), findsOneWidget);

    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1')]);
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.text('Playlist'), findsOneWidget);
  });

  testWidgets('liste les playlists et permet d\'y naviguer', (tester) async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1', name: 'Chill mix')]);

    await _pump(tester, repository: repository);
    await tester.pump();

    await tester.tap(find.text('Chill mix'));
    await tester.pumpAndSettle();

    expect(find.text('Playlist p1'), findsOneWidget);
  });

  testWidgets('creer une playlist appelle create puis rafraichit', (tester) async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);
    await _pump(tester, repository: repository);
    await tester.pump();

    when(() => repository.createPlaylist(name: 'New mix', isPublic: false))
        .thenAnswer((_) async => _playlist('p2', name: 'New mix'));
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p2', name: 'New mix')]);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'New mix');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    verify(() => repository.createPlaylist(name: 'New mix', isPublic: false)).called(1);
    expect(find.text('New mix'), findsOneWidget);
    expect(find.text('Playlist created'), findsOneWidget);
  });

  testWidgets('creer sans nom ne fait rien', (tester) async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);
    await _pump(tester, repository: repository);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    verifyNever(() => repository.createPlaylist(name: any(named: 'name'), isPublic: any(named: 'isPublic')));
    expect(find.text('Create Playlist'), findsOneWidget);
  });

  testWidgets('annuler la creation ferme le dialogue sans appel', (tester) async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);
    await _pump(tester, repository: repository);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repository.createPlaylist(name: any(named: 'name'), isPublic: any(named: 'isPublic')));
    expect(find.text('Create Playlist'), findsNothing);
  });

  testWidgets('supprimer une playlist demande confirmation puis rafraichit', (tester) async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1', name: 'To delete')]);
    await _pump(tester, repository: repository);
    await tester.pump();

    when(() => repository.deletePlaylist('p1')).thenAnswer((_) async {});
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Delete Playlist'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    verify(() => repository.deletePlaylist('p1')).called(1);
    expect(find.text('No playlists yet'), findsOneWidget);
  });

  testWidgets('annuler la suppression garde la playlist', (tester) async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1', name: 'Keep me')]);
    await _pump(tester, repository: repository);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => repository.deletePlaylist(any()));
    expect(find.text('Keep me'), findsOneWidget);
  });
}
