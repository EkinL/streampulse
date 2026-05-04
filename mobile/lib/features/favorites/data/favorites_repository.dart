import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../streams/domain/stream_model.dart';

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  return FavoritesRepository(ref.read(dioProvider));
});

class FavoritesRepository {
  final Dio _dio;

  FavoritesRepository(this._dio);

  Future<List<StreamModel>> listFavorites() async {
    try {
      final response = await _dio.get(ApiEndpoints.favorites);
      final body = response.data as Map<String, dynamic>;
      final items = body['data'] as List<dynamic>? ?? [];
      return items
          .map((e) => StreamModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<void> addFavorite(String streamId) async {
    try {
      await _dio.post(ApiEndpoints.favorite(streamId));
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<void> removeFavorite(String streamId) async {
    try {
      await _dio.delete(ApiEndpoints.favorite(streamId));
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }
}
