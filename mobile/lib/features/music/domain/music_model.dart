class MusicModel {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int duration;
  final String url;
  final String? coverUrl;
  final String uploadedBy;
  final DateTime createdAt;

  const MusicModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.url,
    this.coverUrl,
    required this.uploadedBy,
    required this.createdAt,
  });

  factory MusicModel.fromJson(Map<String, dynamic> json) {
    return MusicModel(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      url: json['url'] as String,
      coverUrl: json['cover_url'] as String?,
      uploadedBy: json['uploaded_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get formattedDuration {
    final m = duration ~/ 60;
    final s = duration % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
