import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/stream_model.dart';

final streamRepositoryProvider = Provider<StreamRepository>((ref) {
  return StreamRepository(ref.read(dioProvider));
});

class StreamRepository {
  final Dio _dio;

  StreamRepository(this._dio);

  Future<List<StreamModel>> listStreams({
    int page = 1,
    int perPage = 20,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.streams,
        queryParameters: {'page': page, 'per_page': perPage},
      );
      final body = response.data as Map<String, dynamic>;
      final items = body['data'] as List<dynamic>? ?? [];
      return items
          .map((e) => StreamModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<StreamModel> getStream(String id) async {
    try {
      final response = await _dio.get(ApiEndpoints.stream(id));
      final body = response.data as Map<String, dynamic>;
      return StreamModel.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<StreamModel> createStream({
    required String title,
    required String description,
    String format = 'mp3',
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.streams,
        data: {
          'title': title,
          'description': description,
          'format': format,
        },
      );
      final body = response.data as Map<String, dynamic>;
      return StreamModel.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<void> startStream(String id) async {
    try {
      await _dio.post(ApiEndpoints.streamStart(id));
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<void> stopStream(String id) async {
    try {
      await _dio.post(ApiEndpoints.streamStop(id));
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<StreamModel> updateStream({
    required String id,
    required String title,
    required String description,
  }) async {
    try {
      final response = await _dio.put(
        ApiEndpoints.stream(id),
        data: {
          'title': title,
          'description': description,
        },
      );
      final body = response.data as Map<String, dynamic>;
      return StreamModel.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }
}
