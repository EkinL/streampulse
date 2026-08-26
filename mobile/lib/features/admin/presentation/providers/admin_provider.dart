import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/domain/user_model.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';

final adminProvider =
    StateNotifierProvider<AdminNotifier, AsyncValue<List<UserModel>>>((ref) {
  return AdminNotifier(ref.read(dioProvider));
});

class AdminNotifier extends StateNotifier<AsyncValue<List<UserModel>>> {
  final Dio _dio;

  AdminNotifier(this._dio) : super(const AsyncValue.loading()) {
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.get(ApiEndpoints.adminUsers);
      final body = response.data as Map<String, dynamic>;
      final items = body['data'] as List<dynamic>? ?? [];
      final users = items
          .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(users);
    } on DioException catch (e, st) {
      state = AsyncValue.error(e.toApiException().message, st);
    } catch (e, st) {
      state = AsyncValue.error(e.toString(), st);
    }
  }

  Future<void> updateRole({
    required String userId,
    required String role,
  }) async {
    try {
      await _dio.put(
        ApiEndpoints.adminUser(userId),
        data: {'role': role},
      );
      await fetchUsers();
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }
}
