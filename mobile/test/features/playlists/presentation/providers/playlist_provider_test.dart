import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/playlists/data/playlist_repository.dart';
import 'package:streampulse/features/playlists/domain/playlist_model.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_provider.dart';

class _MockPlaylistRepository extends Mock implements PlaylistRepository {}

PlaylistModel _playlist(String id) => PlaylistModel(
      id: id,
      name: 'Playlist $id',
      ownerId: 'u1',
      isPublic: false,
      tracks: const [],
      createdAt: DateTime(2026),
    );

void main() {
  late _MockPlaylistRepository repository;

  setUp(() {
    repository = _MockPlaylistRepository();
  });

  test('playlistListProvider construit un PlaylistNotifier branche sur le repository reel', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1')]);
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    expect(container.read(playlistListProvider.notifier), isA<PlaylistNotifier>());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(playlistListProvider).value, hasLength(1));
  });

  test('playlistDetailProvider recupere une playlist via le repository reel', () async {
    when(() => repository.getPlaylist('p1')).thenAnswer((_) async => _playlist('p1'));
    final container = ProviderContainer(
      overrides: [playlistRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final result = await container.read(playlistDetailProvider('p1').future);

    expect(result.id, 'p1');
  });

  test('fetch declenche au demarrage et expose la liste en data', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1')]);

    final notifier = PlaylistNotifier(repository);

    expect(notifier.state.isLoading, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.value, hasLength(1));
  });

  test('fetch en erreur API : etat error avec le message du serveur', () async {
    when(() => repository.listPlaylists())
        .thenThrow(const ApiException(message: 'boom', statusCode: 500));

    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.hasError, isTrue);
    expect(notifier.state.error, 'boom');
  });

  test('create rafraichit la liste apres succes', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);
    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.createPlaylist(name: 'New', isPublic: false))
        .thenAnswer((_) async => _playlist('p1'));
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1')]);

    await notifier.create(name: 'New');

    expect(notifier.state.value, hasLength(1));
  });

  test('create propage l\'exception sans rafraichir', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);
    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.createPlaylist(name: 'New', isPublic: false))
        .thenThrow(const ApiException(message: 'boom'));

    await expectLater(() => notifier.create(name: 'New'), throwsA(isA<ApiException>()));
    verify(() => repository.listPlaylists()).called(1);
  });

  test('update transmet uniquement les champs fournis puis rafraichit', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);
    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.updatePlaylist(id: 'p1', name: 'Renamed', isPublic: null))
        .thenAnswer((_) async => _playlist('p1'));
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1')]);

    await notifier.update(id: 'p1', name: 'Renamed');

    verify(() => repository.updatePlaylist(id: 'p1', name: 'Renamed', isPublic: null)).called(1);
    expect(notifier.state.value, hasLength(1));
  });

  test('delete rafraichit la liste apres succes', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1')]);
    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.deletePlaylist('p1')).thenAnswer((_) async {});
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);

    await notifier.delete('p1');

    expect(notifier.state.value, isEmpty);
  });

  test('addTrack rafraichit la liste apres succes', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);
    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.addTrack(
          playlistId: 'p1',
          title: 'Track',
          url: 'u',
          duration: 90,
        )).thenAnswer((_) async {});
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1')]);

    await notifier.addTrack(playlistId: 'p1', title: 'Track', url: 'u', duration: 90);

    expect(notifier.state.value, hasLength(1));
  });

  test('reorderTracks ne rafraichit pas la liste', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1')]);
    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.reorderTracks(playlistId: 'p1', trackIds: ['t2', 't1']))
        .thenAnswer((_) async => _playlist('p1'));

    await notifier.reorderTracks(playlistId: 'p1', trackIds: ['t2', 't1']);

    verify(() => repository.listPlaylists()).called(1);
  });

  test('reorderTracks propage l\'exception', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);
    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.reorderTracks(playlistId: 'p1', trackIds: ['t1']))
        .thenThrow(const ApiException(message: 'boom'));

    await expectLater(
      () => notifier.reorderTracks(playlistId: 'p1', trackIds: ['t1']),
      throwsA(isA<ApiException>()),
    );
  });

  test('removeTrack rafraichit la liste apres succes', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => [_playlist('p1')]);
    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.removeTrack(playlistId: 'p1', trackId: 't1')).thenAnswer((_) async {});
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);

    await notifier.removeTrack(playlistId: 'p1', trackId: 't1');

    expect(notifier.state.value, isEmpty);
  });

  test('removeTrack propage l\'exception sans rafraichir', () async {
    when(() => repository.listPlaylists()).thenAnswer((_) async => []);
    final notifier = PlaylistNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.removeTrack(playlistId: 'p1', trackId: 't1'))
        .thenThrow(const ApiException(message: 'boom'));

    await expectLater(
      () => notifier.removeTrack(playlistId: 'p1', trackId: 't1'),
      throwsA(isA<ApiException>()),
    );
    verify(() => repository.listPlaylists()).called(1);
  });
}
