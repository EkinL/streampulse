import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/network/api_client.dart';
import 'package:streampulse/core/network/api_exceptions.dart';

DioException _errorWithData(int? statusCode, dynamic data, {String message = 'Http error'}) {
  return DioException(
    requestOptions: RequestOptions(path: '/x'),
    message: message,
    response: statusCode == null
        ? null
        : Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: statusCode,
            data: data,
          ),
  );
}

void main() {
  group('toApiException — message du serveur', () {
    test('utilise error.message quand data.error est une map', () {
      final e = _errorWithData(400, {
        'error': {'message': 'Champ invalide'},
      });
      expect(e.toApiException().message, 'Champ invalide');
    });

    test('utilise data.message quand il n\'y a pas de map error', () {
      final e = _errorWithData(400, {'message': 'Requete invalide'});
      expect(e.toApiException().message, 'Requete invalide');
    });

    test('ignore data quand ce n\'est pas une map', () {
      final e = _errorWithData(500, 'server exploded');
      expect(e.toApiException().message, 'An internal server error occurred.');
    });
  });

  group('toApiException — mapping par statusCode', () {
    test('401 -> UnauthorizedException', () {
      final e = _errorWithData(401, null);
      expect(e.toApiException(), isA<UnauthorizedException>());
    });

    test('404 -> NotFoundException', () {
      final e = _errorWithData(404, null);
      expect(e.toApiException(), isA<NotFoundException>());
    });

    test('409 -> ApiException generique avec le statusCode conserve', () {
      final e = _errorWithData(409, {'message': 'Deja existant'});
      final ex = e.toApiException();
      expect(ex, isA<ApiException>());
      expect(ex, isNot(isA<NotFoundException>()));
      expect(ex.statusCode, 409);
      expect(ex.message, 'Deja existant');
    });

    test('500 -> ServerException', () {
      final e = _errorWithData(500, null);
      expect(e.toApiException(), isA<ServerException>());
    });

    test('statusCode inconnu utilise le message par defaut de DioException', () {
      final e = _errorWithData(null, null, message: 'Failed host lookup');
      final ex = e.toApiException();
      expect(ex.statusCode, isNull);
      expect(ex.message, 'Failed host lookup');
    });

    test('statusCode inconnu sans reponse ni message utilise le message generique', () {
      final e = DioException(requestOptions: RequestOptions(path: '/x'));
      final ex = e.toApiException();
      expect(ex.message, 'An unexpected error occurred.');
    });
  });

  group('messages par defaut des sous-classes', () {
    test('UnauthorizedException expose statusCode 401 et un message par defaut', () {
      const ex = UnauthorizedException();
      expect(ex.statusCode, 401);
      expect(ex.message, 'Unauthorized. Please log in again.');
      expect(ex.toString(), contains('401'));
    });

    test('NotFoundException expose statusCode 404 et un message par defaut', () {
      const ex = NotFoundException();
      expect(ex.statusCode, 404);
      expect(ex.message, 'Resource not found.');
    });

    test('ServerException expose statusCode 500 et un message par defaut', () {
      const ex = ServerException();
      expect(ex.statusCode, 500);
      expect(ex.message, 'An internal server error occurred.');
    });
  });
}
