import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/secure_storage.dart';
import 'api_exceptions.dart';
import 'session_refresher.dart';
import 'trace_context.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://localhost:8080',
      ),
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  final secureStorage = ref.read(secureStorageProvider);
  final session = ref.read(sessionRefresherProvider);

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await secureStorage.getAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        options.headers['traceparent'] = generateTraceparent();
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 &&
            await secureStorage.getRefreshToken() != null) {
          final newAccessToken = await session.refresh();
          if (newAccessToken == null) {
            return handler.reject(
              DioException(
                requestOptions: error.requestOptions,
                error: const UnauthorizedException(),
              ),
            );
          }

          error.requestOptions.headers['Authorization'] =
              'Bearer $newAccessToken';
          try {
            return handler.resolve(await dio.fetch(error.requestOptions));
          } on DioException catch (e) {
            return handler.reject(e);
          }
        }
        handler.next(error);
      },
    ),
  );

  dio.interceptors.add(
    LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => debugPrint('[API] $obj'),
    ),
  );

  return dio;
});

extension DioErrorHandler on DioException {
  String? get _serverMessage {
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        return error['message'] as String?;
      }
      return data['message'] as String?;
    }
    return null;
  }

  ApiException toApiException() {
    final msg = _serverMessage;
    switch (response?.statusCode) {
      case 401:
        return UnauthorizedException(message: msg ?? 'Unauthorized. Please log in again.');
      case 404:
        return NotFoundException(message: msg ?? 'Resource not found.');
      case 409:
        return ApiException(message: msg ?? 'Resource already exists.', statusCode: 409);
      case 500:
        return ServerException(message: msg ?? 'An internal server error occurred.');
      default:
        return ApiException(
          message: msg ?? message ?? 'An unexpected error occurred.',
          statusCode: response?.statusCode,
        );
    }
  }
}
