import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(dioProvider));
});

class AuthRepository {
  final Dio _dio;

  AuthRepository(this._dio);

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.authRegister,
        data: {
          'username': username,
          'email': email,
          'password': password,
        },
      );
      final body = response.data as Map<String, dynamic>;
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.authLogin,
        data: {
          'email': email,
          'password': password,
        },
      );
      final body = response.data as Map<String, dynamic>;
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.authRefresh,
        data: {'refresh_token': refreshToken},
      );
      final body = response.data as Map<String, dynamic>;
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }
}
