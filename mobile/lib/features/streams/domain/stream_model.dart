class StreamModel {
  final String id;
  final String title;
  final String description;
  final String ownerId;
  final String status;
  final int listenerCount;
  final String format;
  final DateTime createdAt;

  const StreamModel({
    required this.id,
    required this.title,
    required this.description,
    required this.ownerId,
    required this.status,
    required this.listenerCount,
    required this.format,
    required this.createdAt,
  });

  factory StreamModel.fromJson(Map<String, dynamic> json) {
    return StreamModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      ownerId: json['owner_id'] as String,
      status: json['status'] as String,
      listenerCount: json['listener_count'] as int? ?? 0,
      format: json['format'] as String? ?? 'mp3',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isLive => status == 'live';

  /// SSE listen URL built from stream ID
  String get listenUrl => '/streams/$id/listen';

  StreamModel copyWith({
    String? id,
    String? title,
    String? description,
    String? ownerId,
    String? status,
    int? listenerCount,
    String? format,
    DateTime? createdAt,
  }) {
    return StreamModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      status: status ?? this.status,
      listenerCount: listenerCount ?? this.listenerCount,
      format: format ?? this.format,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
