import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/playlists/domain/playlist_model.dart';

void main() {
  group('TrackModel.fromJson', () {
    test('lit tous les champs fournis', () {
      final track = TrackModel.fromJson({
        'id': 't1',
        'title': 'Track',
        'url': 'https://cdn/t1.mp3',
        'duration': 125,
        'position': 2,
      });

      expect(track.id, 't1');
      expect(track.title, 'Track');
      expect(track.url, 'https://cdn/t1.mp3');
      expect(track.duration, 125);
      expect(track.position, 2);
    });

    test('applique les valeurs par defaut pour duration et position', () {
      final track = TrackModel.fromJson({
        'id': 't1',
        'title': 'Track',
        'url': 'https://cdn/t1.mp3',
      });

      expect(track.duration, 0);
      expect(track.position, 0);
    });

    test('formattedDuration formate m:ss avec padding', () {
      final track = TrackModel.fromJson({
        'id': 't1',
        'title': 'Track',
        'url': 'u',
        'duration': 65,
      });
      expect(track.formattedDuration, '1:05');
    });
  });

  group('PlaylistModel.fromJson', () {
    test('lit une playlist avec ses pistes', () {
      final playlist = PlaylistModel.fromJson({
        'id': 'p1',
        'name': 'My playlist',
        'owner_id': 'u1',
        'is_public': true,
        'created_at': '2026-01-15T10:00:00Z',
        'tracks': [
          {'id': 't1', 'title': 'A', 'url': 'u1', 'duration': 10, 'position': 0},
          {'id': 't2', 'title': 'B', 'url': 'u2', 'duration': 20, 'position': 1},
        ],
      });

      expect(playlist.id, 'p1');
      expect(playlist.name, 'My playlist');
      expect(playlist.ownerId, 'u1');
      expect(playlist.isPublic, isTrue);
      expect(playlist.createdAt, DateTime.parse('2026-01-15T10:00:00Z'));
      expect(playlist.tracks, hasLength(2));
      expect(playlist.tracks.first.title, 'A');
      expect(playlist.trackCount, 2);
    });

    test('applique les valeurs par defaut quand tracks et is_public manquent', () {
      final playlist = PlaylistModel.fromJson({
        'id': 'p1',
        'name': 'Empty',
        'owner_id': 'u1',
        'created_at': '2026-01-15T10:00:00Z',
      });

      expect(playlist.isPublic, isFalse);
      expect(playlist.tracks, isEmpty);
      expect(playlist.trackCount, 0);
    });
  });

  group('PlaylistModel.copyWith', () {
    final base = PlaylistModel.fromJson({
      'id': 'p1',
      'name': 'Original',
      'owner_id': 'u1',
      'is_public': false,
      'created_at': '2026-01-15T10:00:00Z',
    });

    test('sans argument conserve les valeurs', () {
      final copy = base.copyWith();
      expect(copy.name, base.name);
      expect(copy.isPublic, base.isPublic);
    });

    test('ne modifie que les champs fournis', () {
      final copy = base.copyWith(name: 'Renamed', isPublic: true);
      expect(copy.name, 'Renamed');
      expect(copy.isPublic, isTrue);
      expect(copy.id, base.id);
      expect(copy.ownerId, base.ownerId);
      expect(copy.tracks, base.tracks);
      expect(copy.createdAt, base.createdAt);
    });
  });
}
