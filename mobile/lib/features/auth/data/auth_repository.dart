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
    required bool acceptedTerms,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.authRegister,
        data: {
          'username': username,
          'email': email,
          'password': password,
          'accepted_terms': acceptedTerms,
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

  /// Connexion sociale : envoie l'ID token obtenu du SDK Google ou Apple,
  /// le serveur le verifie et rend la meme paire de jetons que le login.
  Future<Map<String, dynamic>> oauthLogin({
    required String provider,
    required String idToken,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.authOAuth,
        data: {
          'provider': provider,
          'id_token': idToken,
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

  /// Efface le compte connecte et tout ce qui s'y rattache, cote serveur
  /// (droit a l'effacement, docs/rgpd.md). Le jeton est pose par
  /// l'intercepteur du client HTTP.
  Future<void> deleteAccount() async {
    try {
      await _dio.delete(ApiEndpoints.usersMe);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  /// Change l'email et le nom d'utilisateur du compte connecte (droit de
  /// rectification, docs/rgpd.md).
  Future<Map<String, dynamic>> updateProfile({
    required String email,
    required String username,
  }) async {
    try {
      final response = await _dio.patch(
        ApiEndpoints.usersMe,
        data: {'email': email, 'username': username},
      );
      final body = response.data as Map<String, dynamic>;
      return body['data'] as Map<String, dynamic>;
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }
}
