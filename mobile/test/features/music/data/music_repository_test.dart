import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/music/data/music_repository.dart';

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

Map<String, dynamic> _musicJson({String id = 'm1'}) => {
      'id': id,
      'title': 'Title',
      'artist': 'Artist',
      'url': 'https://cdn/$id.mp3',
      'uploaded_by': 'u1',
      'created_at': '2026-01-15T10:00:00Z',
    };

Map<String, dynamic> _streamJson({String id = 's1'}) => {
      'id': id,
      'title': 'Stream',
      'owner_id': 'u1',
      'status': 'live',
      'created_at': '2026-01-15T10:00:00Z',
    };

void main() {
  late _MockDio dio;
  late MusicRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = MusicRepository(dio);
  });

  test('listMusic utilise la pagination par defaut et parse la liste', () async {
    when(() => dio.get(
          ApiEndpoints.music,
          queryParameters: {'page': 1, 'per_page': 20},
        )).thenAnswer((_) async => _response({
          'data': [_musicJson(), _musicJson(id: 'm2')],
        }));

    final tracks = await repository.listMusic();

    expect(tracks.map((t) => t.id), ['m1', 'm2']);
  });

  test('getMusic parse un morceau unique', () async {
    when(() => dio.get(ApiEndpoints.musicItem('m1')))
        .thenAnswer((_) async => _response({'data': _musicJson()}));

    final track = await repository.getMusic('m1');

    expect(track.id, 'm1');
  });

  test('getMusic traduit un 404 en NotFoundException', () async {
    when(() => dio.get(ApiEndpoints.musicItem('missing')))
        .thenThrow(_errorResponse(404));

    expect(() => repository.getMusic('missing'), throwsA(isA<NotFoundException>()));
  });

  test('searchMusic envoie la requete en query param', () async {
    when(() => dio.get(
          ApiEndpoints.musicSearch,
          queryParameters: {'q': 'daft punk'},
        )).thenAnswer((_) async => _response({
          'data': [_musicJson()],
        }));

    final results = await repository.searchMusic('daft punk');

    expect(results, hasLength(1));
  });

  test('uploadMusic envoie un FormData avec le fichier et les metadonnees', () async {
    when(() => dio.post(ApiEndpoints.music, data: any(named: 'data')))
        .thenAnswer((invocation) async {
      final formData = invocation.namedArguments[#data] as FormData;
      final fields = Map.fromEntries(formData.fields);
      expect(formData.files, hasLength(1));
      expect(formData.files.first.key, 'file');
      expect(fields['title'], 'Uploaded');
      expect(fields['artist'], 'Someone');
      return _response({'data': _musicJson()});
    });

    final track = await repository.uploadMusic(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'track.mp3',
      title: 'Uploaded',
      artist: 'Someone',
    );

    expect(track.id, 'm1');
  });

  test('addMusicByUrl envoie les champs attendus', () async {
    when(() => dio.post(
          ApiEndpoints.music,
          data: {
            'title': 'By URL',
            'artist': 'Someone',
            'album': '',
            'duration': 120,
            'url': 'https://cdn/track.mp3',
          },
        )).thenAnswer((_) async => _response({'data': _musicJson()}));

    final track = await repository.addMusicByUrl(
      title: 'By URL',
      artist: 'Someone',
      url: 'https://cdn/track.mp3',
      duration: 120,
    );

    expect(track.id, 'm1');
  });

  test('globalSearch parse a la fois streams et music', () async {
    when(() => dio.get(
          ApiEndpoints.globalSearch,
          queryParameters: {'q': 'live'},
        )).thenAnswer((_) async => _response({
          'data': {
            'streams': [_streamJson()],
            'music': [_musicJson()],
          },
        }));

    final result = await repository.globalSearch('live');

    expect(result.streams, hasLength(1));
    expect(result.music, hasLength(1));
    expect(result.streams.first.id, 's1');
    expect(result.music.first.id, 'm1');
  });

  test('globalSearch renvoie des listes vides quand streams/music sont absents', () async {
    when(() => dio.get(
          ApiEndpoints.globalSearch,
          queryParameters: {'q': 'nothing'},
        )).thenAnswer((_) async => _response({'data': <String, dynamic>{}}));

    final result = await repository.globalSearch('nothing');

    expect(result.streams, isEmpty);
    expect(result.music, isEmpty);
  });
}
