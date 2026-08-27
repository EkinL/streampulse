import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/music_model.dart';
import '../../streams/domain/stream_model.dart';

final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  return MusicRepository(ref.read(dioProvider));
});

class MusicRepository {
  final Dio _dio;
  MusicRepository(this._dio);

  Future<List<MusicModel>> listMusic({int page = 1, int perPage = 20}) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.music,
        queryParameters: {'page': page, 'per_page': perPage},
      );
      final body = response.data as Map<String, dynamic>;
      final items = body['data'] as List<dynamic>? ?? [];
      return items.map((e) => MusicModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<MusicModel> getMusic(String id) async {
    try {
      final response = await _dio.get(ApiEndpoints.musicItem(id));
      final body = response.data as Map<String, dynamic>;
      return MusicModel.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<List<MusicModel>> searchMusic(String query) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.musicSearch,
        queryParameters: {'q': query},
      );
      final body = response.data as Map<String, dynamic>;
      final items = body['data'] as List<dynamic>? ?? [];
      return items.map((e) => MusicModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<MusicModel> uploadMusic({
    required Uint8List bytes,
    required String filename,
    required String title,
    required String artist,
    String album = '',
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
        'title': title,
        'artist': artist,
        'album': album,
      });
      final response = await _dio.post(ApiEndpoints.music, data: formData);
      final body = response.data as Map<String, dynamic>;
      return MusicModel.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<MusicModel> addMusicByUrl({
    required String title,
    required String artist,
    required String url,
    int duration = 0,
    String album = '',
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.music,
        data: {
          'title': title,
          'artist': artist,
          'album': album,
          'duration': duration,
          'url': url,
        },
      );
      final body = response.data as Map<String, dynamic>;
      return MusicModel.fromJson(body['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }

  Future<({List<StreamModel> streams, List<MusicModel> music})> globalSearch(String query) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.globalSearch,
        queryParameters: {'q': query},
      );
      final body = response.data as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>;
      final streamList = (data['streams'] as List<dynamic>? ?? [])
          .map((e) => StreamModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final musicList = (data['music'] as List<dynamic>? ?? [])
          .map((e) => MusicModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return (streams: streamList, music: musicList);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }
}
