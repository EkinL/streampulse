/// Mirrors `dto.FeedbackResponse` on the backend: a signalement as read back
/// from `POST /feedback` or listed via `GET /admin/feedback`.
class FeedbackModel {
  final String id;
  final String userId;
  final String type;
  final String message;
  final String? appVersion;
  final String? platform;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FeedbackModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    this.appVersion,
    this.platform,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FeedbackModel.fromJson(Map<String, dynamic> json) => FeedbackModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        type: json['type'] as String,
        message: json['message'] as String,
        appVersion: json['app_version'] as String?,
        platform: json['platform'] as String?,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
