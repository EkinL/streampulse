import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/favorites/data/favorites_repository.dart';

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

void main() {
  late _MockDio dio;
  late FavoritesRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = FavoritesRepository(dio);
  });

  group('listFavorites', () {
    test('parse la liste de streams favoris', () async {
      when(() => dio.get(ApiEndpoints.favorites)).thenAnswer((_) async => _response({
            'data': [
              {
                'id': 's1',
                'title': 'Stream 1',
                'owner_id': 'u1',
                'status': 'live',
                'created_at': '2026-01-15T10:00:00Z',
              },
            ],
          }));

      final favorites = await repository.listFavorites();

      expect(favorites, hasLength(1));
      expect(favorites.first.id, 's1');
      expect(favorites.first.isLive, isTrue);
    });

    test('renvoie une liste vide quand data est absent', () async {
      when(() => dio.get(ApiEndpoints.favorites))
          .thenAnswer((_) async => _response(<String, dynamic>{}));

      expect(await repository.listFavorites(), isEmpty);
    });

    test('traduit une erreur reseau en ApiException', () async {
      when(() => dio.get(ApiEndpoints.favorites)).thenThrow(_errorResponse(500));

      expect(() => repository.listFavorites(), throwsA(isA<ServerException>()));
    });
  });

  group('addFavorite', () {
    test('appelle POST /favorites/:id', () async {
      when(() => dio.post(ApiEndpoints.favorite('s1')))
          .thenAnswer((_) async => _response(null));

      await repository.addFavorite('s1');

      verify(() => dio.post(ApiEndpoints.favorite('s1'))).called(1);
    });

    test('propage une ApiException en cas d\'echec', () async {
      when(() => dio.post(ApiEndpoints.favorite('s1'))).thenThrow(_errorResponse(404));

      expect(() => repository.addFavorite('s1'), throwsA(isA<NotFoundException>()));
    });
  });

  group('removeFavorite', () {
    test('appelle DELETE /favorites/:id', () async {
      when(() => dio.delete(ApiEndpoints.favorite('s1')))
          .thenAnswer((_) async => _response(null));

      await repository.removeFavorite('s1');

      verify(() => dio.delete(ApiEndpoints.favorite('s1'))).called(1);
    });

    test('propage une ApiException en cas d\'echec', () async {
      when(() => dio.delete(ApiEndpoints.favorite('s1'))).thenThrow(_errorResponse(404));

      expect(() => repository.removeFavorite('s1'), throwsA(isA<NotFoundException>()));
    });
  });
}
