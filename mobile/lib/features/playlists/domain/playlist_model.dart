class PlaylistModel {
  final String id;
  final String name;
  final String ownerId;
  final String? ownerUsername;
  final bool isPublic;
  final List<TrackModel> tracks;
  final int trackCount;
  final DateTime createdAt;

  const PlaylistModel({
    required this.id,
    required this.name,
    required this.ownerId,
    this.ownerUsername,
    required this.isPublic,
    required this.tracks,
    required this.trackCount,
    required this.createdAt,
  });

  factory PlaylistModel.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? [];
    final tracks = rawTracks
        .map((e) => TrackModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return PlaylistModel(
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['owner_id'] as String,
      // Only present on the public-playlists endpoint, where the owner isn't
      // necessarily the current user.
      ownerUsername: json['owner_username'] as String?,
      isPublic: json['is_public'] as bool? ?? false,
      tracks: tracks,
      // The list endpoint doesn't include the full `tracks` relation, only
      // `track_count`. Fall back to tracks.length for endpoints that do.
      trackCount: json['track_count'] as int? ?? tracks.length,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  PlaylistModel copyWith({
    String? id,
    String? name,
    String? ownerId,
    String? ownerUsername,
    bool? isPublic,
    List<TrackModel>? tracks,
    int? trackCount,
    DateTime? createdAt,
  }) {
    return PlaylistModel(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      ownerUsername: ownerUsername ?? this.ownerUsername,
      isPublic: isPublic ?? this.isPublic,
      tracks: tracks ?? this.tracks,
      trackCount: trackCount ?? tracks?.length ?? this.trackCount,
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
