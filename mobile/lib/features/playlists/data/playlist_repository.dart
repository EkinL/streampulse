import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/playlist_model.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(ref.read(dioProvider));
});

class PlaylistRepository {
  final Dio _dio;

  PlaylistRepository(this._dio);

  Future<List<PlaylistModel>> listPlaylists() async {
    try {
      final response = await _dio.get(ApiEndpoints.playlists);
      final body = response.data as Map<String, dynamic>;
      final items = body['data'] as List<dynamic>? ?? [];
      return items
          .map((e) => PlaylistModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<PlaylistModel> getPlaylist(String id) async {
    try {
      final response = await _dio.get(ApiEndpoints.playlist(id));
      final body = response.data as Map<String, dynamic>;
      return PlaylistModel.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<PlaylistModel> createPlaylist({
    required String name,
    bool isPublic = false,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.playlists,
        data: {
          'name': name,
          'is_public': isPublic,
        },
      );
      final body = response.data as Map<String, dynamic>;
      return PlaylistModel.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<PlaylistModel> updatePlaylist({
    required String id,
    String? name,
    bool? isPublic,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (isPublic != null) data['is_public'] = isPublic;

      final response = await _dio.put(
        ApiEndpoints.playlist(id),
        data: data,
      );
      final body = response.data as Map<String, dynamic>;
      return PlaylistModel.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<void> deletePlaylist(String id) async {
    try {
      await _dio.delete(ApiEndpoints.playlist(id));
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<void> addTrack({
    required String playlistId,
    required String title,
    required String url,
    required int duration,
  }) async {
    try {
      await _dio.post(
        ApiEndpoints.playlistTracks(playlistId),
        data: {
          'title': title,
          'url': url,
          'duration': duration,
        },
      );
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<void> removeTrack({
    required String playlistId,
    required String trackId,
  }) async {
    try {
      await _dio.delete(
        ApiEndpoints.playlistTrack(playlistId, trackId),
      );
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }
}
