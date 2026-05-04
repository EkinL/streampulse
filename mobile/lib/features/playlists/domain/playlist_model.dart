class PlaylistModel {
  final String id;
  final String name;
  @override
  final String ownerId;
  final bool isPublic;
  final List<TrackModel> tracks;
  final DateTime createdAt;

  const PlaylistModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.isPublic,
    required this.tracks,
    required this.createdAt,
  });

  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? [];
    return PlaylistModel(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['owner_id'] as String,
      isPublic: json['is_public'] as bool? ?? false,
      tracks: rawTracks
          .map((e) => TrackModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  int get trackCount => tracks.length;

  PlaylistModel copyWith({
    String? id,
    String? name,
    String? ownerId,
    bool? isPublic,
    List<TrackModel>? tracks,
    DateTime? createdAt,
  }) {
    return PlaylistModel(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      isPublic: isPublic ?? this.isPublic,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class TrackModel {
  final String id;
  final String title;
  final String url;
  final int duration;
  final int position;

  const TrackModel({
    required this.id,
    required this.title,
    required this.url,
    required this.duration,
    required this.position,
  });

  factory TrackModel.fromJson(Map<String, dynamic> json) {
    return TrackModel(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      duration: json['duration'] as int? ?? 0,
      position: json['position'] as int? ?? 0,
    );
  }

  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
