import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/playlists/data/playlist_repository.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _response<T>(T data, {int statusCode = 200}) => Response<T>(
      requestOptions: RequestOptions(path: ''),
      statusCode: statusCode,
      data: data,
    );

DioException _errorResponse(int statusCode) => DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: statusCode,
      ),
    );

Map<String, dynamic> _playlistJson({String id = 'p1'}) => {
      'id': id,
      'name': 'Playlist',
      'owner_id': 'u1',
      'is_public': false,
      'created_at': '2026-01-15T10:00:00Z',
      'tracks': <dynamic>[],
    };

void main() {
  late _MockDio dio;
  late PlaylistRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = PlaylistRepository(dio);
  });

  test('listPlaylists parse la liste', () async {
    when(() => dio.get(ApiEndpoints.playlists)).thenAnswer((_) async => _response({
          'data': [_playlistJson(), _playlistJson(id: 'p2')],
        }));

    final playlists = await repository.listPlaylists();

    expect(playlists.map((p) => p.id), ['p1', 'p2']);
  });

  test('listPlaylists traduit une erreur en ApiException', () async {
    when(() => dio.get(ApiEndpoints.playlists)).thenThrow(_errorResponse(500));

    expect(() => repository.listPlaylists(), throwsA(isA<ServerException>()));
  });

  test('getPlaylist parse une playlist unique', () async {
    when(() => dio.get(ApiEndpoints.playlist('p1')))
        .thenAnswer((_) async => _response({'data': _playlistJson()}));

    final playlist = await repository.getPlaylist('p1');

    expect(playlist.id, 'p1');
  });

  test('getPlaylist traduit un 404 en NotFoundException', () async {
    when(() => dio.get(ApiEndpoints.playlist('missing'))).thenThrow(_errorResponse(404));

    expect(() => repository.getPlaylist('missing'), throwsA(isA<NotFoundException>()));
  });

  test('createPlaylist envoie name/is_public par defaut a false', () async {
    when(() => dio.post(
          ApiEndpoints.playlists,
          data: {'name': 'New', 'is_public': false},
        )).thenAnswer((_) async => _response({'data': _playlistJson()}));

    final playlist = await repository.createPlaylist(name: 'New');

    expect(playlist.id, 'p1');
  });

  test('createPlaylist transmet is_public quand fourni', () async {
    when(() => dio.post(
          ApiEndpoints.playlists,
          data: {'name': 'New', 'is_public': true},
        )).thenAnswer((_) async => _response({'data': _playlistJson()}));

    await repository.createPlaylist(name: 'New', isPublic: true);

    verify(() => dio.post(
          ApiEndpoints.playlists,
          data: {'name': 'New', 'is_public': true},
        )).called(1);
  });

  test('createPlaylist propage une ApiException en cas d\'echec', () async {
    when(() => dio.post(ApiEndpoints.playlists, data: any(named: 'data')))
        .thenThrow(_errorResponse(500));

    expect(() => repository.createPlaylist(name: 'New'), throwsA(isA<ServerException>()));
  });

  group('updatePlaylist', () {
    test('n\'envoie que les champs fournis', () async {
      when(() => dio.put(
            ApiEndpoints.playlist('p1'),
            data: {'name': 'Renamed'},
          )).thenAnswer((_) async => _response({'data': _playlistJson()}));

      await repository.updatePlaylist(id: 'p1', name: 'Renamed');

      verify(() => dio.put(
            ApiEndpoints.playlist('p1'),
            data: {'name': 'Renamed'},
          )).called(1);
    });

    test('envoie un corps vide quand aucun champ n\'est fourni', () async {
      when(() => dio.put(
            ApiEndpoints.playlist('p1'),
            data: <String, dynamic>{},
          )).thenAnswer((_) async => _response({'data': _playlistJson()}));

      await repository.updatePlaylist(id: 'p1');

      verify(() => dio.put(
            ApiEndpoints.playlist('p1'),
            data: <String, dynamic>{},
          )).called(1);
    });

    test('transmet isPublic quand fourni', () async {
      when(() => dio.put(
            ApiEndpoints.playlist('p1'),
            data: {'is_public': true},
          )).thenAnswer((_) async => _response({'data': _playlistJson()}));

      await repository.updatePlaylist(id: 'p1', isPublic: true);

      verify(() => dio.put(
            ApiEndpoints.playlist('p1'),
            data: {'is_public': true},
          )).called(1);
    });

    test('propage une ApiException en cas d\'echec', () async {
      when(() => dio.put(ApiEndpoints.playlist('p1'), data: any(named: 'data')))
          .thenThrow(_errorResponse(500));

      expect(() => repository.updatePlaylist(id: 'p1', name: 'x'), throwsA(isA<ServerException>()));
    });
  });

  test('deletePlaylist appelle DELETE /playlists/:id', () async {
    when(() => dio.delete(ApiEndpoints.playlist('p1')))
        .thenAnswer((_) async => _response(null));

    await repository.deletePlaylist('p1');

    verify(() => dio.delete(ApiEndpoints.playlist('p1'))).called(1);
  });

  test('deletePlaylist propage une ApiException en cas d\'echec', () async {
    when(() => dio.delete(ApiEndpoints.playlist('p1'))).thenThrow(_errorResponse(404));

    expect(() => repository.deletePlaylist('p1'), throwsA(isA<NotFoundException>()));
  });

  test('addTrack envoie title/url/duration', () async {
    when(() => dio.post(
          ApiEndpoints.playlistTracks('p1'),
          data: {'title': 'Track', 'url': 'https://cdn/t.mp3', 'duration': 90},
        )).thenAnswer((_) async => _response(null));

    await repository.addTrack(
      playlistId: 'p1',
      title: 'Track',
      url: 'https://cdn/t.mp3',
      duration: 90,
    );

    verify(() => dio.post(
          ApiEndpoints.playlistTracks('p1'),
          data: {'title': 'Track', 'url': 'https://cdn/t.mp3', 'duration': 90},
        )).called(1);
  });

  test('addTrack propage une ApiException en cas d\'echec', () async {
    when(() => dio.post(ApiEndpoints.playlistTracks('p1'), data: any(named: 'data')))
        .thenThrow(_errorResponse(404));

    expect(
      () => repository.addTrack(playlistId: 'p1', title: 't', url: 'u', duration: 1),
      throwsA(isA<NotFoundException>()),
    );
  });

  test('reorderTracks envoie l\'ordre complet et renvoie la playlist mise a jour', () async {
    when(() => dio.put(
          ApiEndpoints.playlistTracks('p1'),
          data: {'track_ids': ['t2', 't1']},
        )).thenAnswer((_) async => _response({'data': _playlistJson()}));

    final playlist = await repository.reorderTracks(
      playlistId: 'p1',
      trackIds: ['t2', 't1'],
    );

    expect(playlist.id, 'p1');
  });

  test('reorderTracks propage une ApiException en cas d\'echec', () async {
    when(() => dio.put(ApiEndpoints.playlistTracks('p1'), data: any(named: 'data')))
        .thenThrow(_errorResponse(500));

    expect(
      () => repository.reorderTracks(playlistId: 'p1', trackIds: ['t1']),
      throwsA(isA<ServerException>()),
    );
  });

  test('removeTrack appelle DELETE /playlists/:id/tracks/:trackId', () async {
    when(() => dio.delete(ApiEndpoints.playlistTrack('p1', 't1')))
        .thenAnswer((_) async => _response(null));

    await repository.removeTrack(playlistId: 'p1', trackId: 't1');

    verify(() => dio.delete(ApiEndpoints.playlistTrack('p1', 't1'))).called(1);
  });

  test('removeTrack propage une ApiException en cas d\'echec', () async {
    when(() => dio.delete(ApiEndpoints.playlistTrack('p1', 't1')))
        .thenThrow(_errorResponse(404));

    expect(
      () => repository.removeTrack(playlistId: 'p1', trackId: 't1'),
      throwsA(isA<NotFoundException>()),
    );
  });
}
