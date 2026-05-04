import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';

class MusicFavoritesNotifier extends StateNotifier<Set<String>> {
  final Dio _dio;

  MusicFavoritesNotifier(this._dio) : super({});

  Future<void> fetch() async {
    try {
      final response = await _dio.get(ApiEndpoints.musicFavoriteIds);
      final body = response.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;
      final ids = (data['ids'] as List<dynamic>).cast<String>();
      state = ids.toSet();
    } on DioException {
      // Silently fail — favorites are non-critical
    }
  }

  Future<void> toggle(String musicId) async {
    try {
      if (state.contains(musicId)) {
        await _dio.delete(ApiEndpoints.musicFavorite(musicId));
        state = {...state}..remove(musicId);
      } else {
        await _dio.post(ApiEndpoints.musicFavorite(musicId));
        state = {...state, musicId};
      }
    } on DioException {
      // Silently fail
    }
  }

  bool isFavorited(String musicId) => state.contains(musicId);
}

final musicFavoritesProvider =
    StateNotifierProvider<MusicFavoritesNotifier, Set<String>>((ref) {
  return MusicFavoritesNotifier(ref.read(dioProvider));
});
