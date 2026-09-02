import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../feedback/domain/feedback_model.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';

final adminFeedbackProvider =
    StateNotifierProvider<AdminFeedbackNotifier, AsyncValue<List<FeedbackModel>>>((ref) {
  return AdminFeedbackNotifier(ref.read(dioProvider));
});

/// Statuses a report can be moved through, in processing order.
const List<String> feedbackStatuses = ['new', 'in_progress', 'resolved'];

class AdminFeedbackNotifier extends StateNotifier<AsyncValue<List<FeedbackModel>>> {
  final Dio _dio;

  /// The filter behind the current state, remembered so `updateStatus` can
  /// refresh the list without dropping whatever the admin was looking at.
  String? _statusFilter;

  AdminFeedbackNotifier(this._dio) : super(const AsyncValue.loading()) {
    fetchFeedback();
  }

  Future<void> fetchFeedback({String? status}) async {
    _statusFilter = status;
    state = const AsyncValue.loading();
    try {
      final response = await _dio.get(
        ApiEndpoints.adminFeedback,
        queryParameters: {
          'per_page': 50,
          if (status != null) 'status': status,
        },
      );
      final body = response.data as Map<String, dynamic>;
      final items = body['data'] as List<dynamic>? ?? [];
      final reports = items
          .map((e) => FeedbackModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(reports);
    } on DioException catch (e, st) {
      state = AsyncValue.error(e.toApiException().message, st);
    } catch (e, st) {
      state = AsyncValue.error(e.toString(), st);
    }
  }

  Future<void> updateStatus({
    required String id,
    required String status,
  }) async {
    try {
      await _dio.put(
        ApiEndpoints.adminFeedbackStatus(id),
        data: {'status': status},
      );
      await fetchFeedback(status: _statusFilter);
    } on DioException catch (e) {
      throw e.toApiException();
    }
  }
}
