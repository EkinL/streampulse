import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_endpoints.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';

class _MockDio extends Mock implements Dio {}

Response<T> _response<T>(T data, {int statusCode = 200}) => Response<T>(
      requestOptions: RequestOptions(path: ''),
      statusCode: statusCode,
      data: data,
    );

DioException _errorResponse(int statusCode, {Map<String, dynamic>? data}) => DioException(
      requestOptions: RequestOptions(path: ''),
      response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: statusCode,
        data: data,
      ),
    );

void main() {
  late _MockDio dio;
  late AuthRepository repository;

  setUp(() {
    dio = _MockDio();
    repository = AuthRepository(dio);
  });

  group('register', () {
    test('envoie username/email/password et renvoie les donnees', () async {
      when(() => dio.post(
            ApiEndpoints.authRegister,
            data: {
              'username': 'alice',
              'email': 'alice@example.com',
              'password': 'secret123',
            },
          )).thenAnswer((_) async => _response({
            'data': {'user': 'created'},
          }));

      final result = await repository.register(
        username: 'alice',
        email: 'alice@example.com',
        password: 'secret123',
      );

      expect(result, {'user': 'created'});
    });

    test('traduit un 409 en ApiException', () async {
      when(() => dio.post(
            ApiEndpoints.authRegister,
            data: any(named: 'data'),
          )).thenThrow(_errorResponse(409));

      expect(
        () => repository.register(
          username: 'alice',
          email: 'alice@example.com',
          password: 'secret123',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('login', () {
    test('envoie email/password et renvoie les donnees', () async {
      when(() => dio.post(
            ApiEndpoints.authLogin,
            data: {'email': 'alice@example.com', 'password': 'secret123'},
          )).thenAnswer((_) async => _response({
            'data': {'access_token': 'a', 'refresh_token': 'r'},
          }));

      final result = await repository.login(
        email: 'alice@example.com',
        password: 'secret123',
      );

      expect(result, {'access_token': 'a', 'refresh_token': 'r'});
    });

    test('traduit un 401 en UnauthorizedException', () async {
      when(() => dio.post(
            ApiEndpoints.authLogin,
            data: any(named: 'data'),
          )).thenThrow(_errorResponse(401));

      expect(
        () => repository.login(email: 'alice@example.com', password: 'wrong'),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  group('refreshToken', () {
    test('envoie le refresh_token et renvoie les nouveaux jetons', () async {
      when(() => dio.post(
            ApiEndpoints.authRefresh,
            data: {'refresh_token': 'old-refresh'},
          )).thenAnswer((_) async => _response({
            'data': {'access_token': 'new-access', 'refresh_token': 'new-refresh'},
          }));

      final result = await repository.refreshToken('old-refresh');

      expect(result, {'access_token': 'new-access', 'refresh_token': 'new-refresh'});
    });

    test('propage une ApiException quand le refresh est rejete', () async {
      when(() => dio.post(
            ApiEndpoints.authRefresh,
            data: any(named: 'data'),
          )).thenThrow(_errorResponse(401));

      expect(
        () => repository.refreshToken('expired'),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  group('deleteAccount', () {
    test('appelle DELETE /users/me', () async {
      when(() => dio.delete(ApiEndpoints.usersMe))
          .thenAnswer((_) async => _response(null));

      await repository.deleteAccount();

      verify(() => dio.delete(ApiEndpoints.usersMe)).called(1);
    });

    test('traduit une erreur serveur en ServerException', () async {
      when(() => dio.delete(ApiEndpoints.usersMe)).thenThrow(_errorResponse(500));

      expect(
        () => repository.deleteAccount(),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
