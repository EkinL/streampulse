import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/streams/data/stream_repository.dart';

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

Map<String, dynamic> _streamJson({
  String id = 's1',
  String status = 'live',
}) =>
    {
      'id': id,
      'title': 'Title',
      'owner_id': 'u1',
      'status': status,
      'created_at': '2026-01-15T10:00:00Z',
    };

void main() {
  late _MockDio dio;
  late StreamRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = StreamRepository(dio);
  });

  group('listStreams', () {
    test('utilise la pagination par defaut et parse la liste', () async {
      when(() => dio.get(
            ApiEndpoints.streams,
            queryParameters: {'page': 1, 'per_page': 20},
          )).thenAnswer((_) async => _response({
            'data': [_streamJson(), _streamJson(id: 's2')],
          }));

      final streams = await repository.listStreams();

      expect(streams, hasLength(2));
      expect(streams.map((s) => s.id), ['s1', 's2']);
    });

    test('transmet la pagination fournie', () async {
      when(() => dio.get(
            ApiEndpoints.streams,
            queryParameters: {'page': 2, 'per_page': 5},
          )).thenAnswer((_) async => _response({'data': <dynamic>[]}));

      final streams = await repository.listStreams(page: 2, perPage: 5);

      expect(streams, isEmpty);
      verify(() => dio.get(
            ApiEndpoints.streams,
            queryParameters: {'page': 2, 'per_page': 5},
          )).called(1);
    });

    test('traduit une erreur en ApiException', () async {
      when(() => dio.get(
            ApiEndpoints.streams,
            queryParameters: any(named: 'queryParameters'),
          )).thenThrow(_errorResponse(500));

      expect(() => repository.listStreams(), throwsA(isA<ServerException>()));
    });
  });

  test('getStream parse un stream unique', () async {
    when(() => dio.get(ApiEndpoints.stream('s1')))
        .thenAnswer((_) async => _response({'data': _streamJson()}));

    final stream = await repository.getStream('s1');

    expect(stream.id, 's1');
    expect(stream.isLive, isTrue);
  });

  test('createStream envoie titre/description/format et renvoie le stream cree', () async {
    when(() => dio.post(
          ApiEndpoints.streams,
          data: {
            'title': 'New stream',
            'description': 'Desc',
            'format': 'aac',
          },
        )).thenAnswer((_) async => _response({'data': _streamJson()}));

    final stream = await repository.createStream(
      title: 'New stream',
      description: 'Desc',
      format: 'aac',
    );

    expect(stream.id, 's1');
  });

  test('createStream utilise mp3 par defaut', () async {
    when(() => dio.post(
          ApiEndpoints.streams,
          data: {
            'title': 'New stream',
            'description': 'Desc',
            'format': 'mp3',
          },
        )).thenAnswer((_) async => _response({'data': _streamJson()}));

    await repository.createStream(title: 'New stream', description: 'Desc');

    verify(() => dio.post(
          ApiEndpoints.streams,
          data: {
            'title': 'New stream',
            'description': 'Desc',
            'format': 'mp3',
          },
        )).called(1);
  });

  test('startStream appelle POST /streams/:id/start', () async {
    when(() => dio.post(ApiEndpoints.streamStart('s1')))
        .thenAnswer((_) async => _response(null));

    await repository.startStream('s1');

    verify(() => dio.post(ApiEndpoints.streamStart('s1'))).called(1);
  });

  test('stopStream appelle POST /streams/:id/stop', () async {
    when(() => dio.post(ApiEndpoints.streamStop('s1')))
        .thenAnswer((_) async => _response(null));

    await repository.stopStream('s1');

    verify(() => dio.post(ApiEndpoints.streamStop('s1'))).called(1);
  });

  test('updateStream envoie titre/description et renvoie le stream mis a jour', () async {
    when(() => dio.put(
          ApiEndpoints.stream('s1'),
          data: {'title': 'Updated', 'description': 'New desc'},
        )).thenAnswer((_) async => _response({'data': _streamJson()}));

    final stream = await repository.updateStream(
      id: 's1',
      title: 'Updated',
      description: 'New desc',
    );

    expect(stream.id, 's1');
  });

  test('updateStream propage une ApiException en cas d\'echec', () async {
    when(() => dio.put(
          ApiEndpoints.stream('s1'),
          data: any(named: 'data'),
        )).thenThrow(_errorResponse(404));

    expect(
      () => repository.updateStream(id: 's1', title: 't', description: 'd'),
      throwsA(isA<NotFoundException>()),
    );
  });
}
