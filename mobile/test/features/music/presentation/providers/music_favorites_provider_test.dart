import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/features/music/presentation/providers/music_favorites_provider.dart';

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
  late MusicFavoritesNotifier notifier;

  setUp(() {
    dio = _MockDio();
    notifier = MusicFavoritesNotifier(dio);
  });

  test('l\'etat initial est un ensemble vide', () {
    expect(notifier.state, isEmpty);
    expect(notifier.isFavorited('m1'), isFalse);
  });

  group('fetch', () {
    test('remplit le state avec les ids favoris', () async {
      when(() => dio.get(ApiEndpoints.musicFavoriteIds)).thenAnswer((_) async => _response({
            'data': {
              'ids': ['m1', 'm2'],
            },
          }));

      await notifier.fetch();

      expect(notifier.state, {'m1', 'm2'});
      expect(notifier.isFavorited('m1'), isTrue);
    });

    test('echoue silencieusement sur une erreur reseau', () async {
      when(() => dio.get(ApiEndpoints.musicFavoriteIds)).thenThrow(_errorResponse(500));

      await notifier.fetch();

      expect(notifier.state, isEmpty);
    });
  });

  group('toggle', () {
    test('ajoute un morceau non favori', () async {
      when(() => dio.post(ApiEndpoints.musicFavorite('m1')))
          .thenAnswer((_) async => _response(null));

      await notifier.toggle('m1');

      expect(notifier.state, {'m1'});
    });

    test('retire un morceau deja favori', () async {
      when(() => dio.get(ApiEndpoints.musicFavoriteIds)).thenAnswer((_) async => _response({
            'data': {
              'ids': ['m1'],
            },
          }));
      await notifier.fetch();

      when(() => dio.delete(ApiEndpoints.musicFavorite('m1')))
          .thenAnswer((_) async => _response(null));

      await notifier.toggle('m1');

      expect(notifier.state, isEmpty);
    });

    test('echoue silencieusement sans modifier le state', () async {
      when(() => dio.post(ApiEndpoints.musicFavorite('m1'))).thenThrow(_errorResponse(500));

      await notifier.toggle('m1');

      expect(notifier.state, isEmpty);
    });
  });
}
