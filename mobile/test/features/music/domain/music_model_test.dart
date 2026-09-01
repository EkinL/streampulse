import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/music/domain/music_model.dart';

void main() {
  group('MusicModel.fromJson', () {
    test('lit tous les champs fournis', () {
      final model = MusicModel.fromJson({
        'id': 'm1',
        'title': 'Title',
        'artist': 'Artist',
        'album': 'Album',
        'duration': 185,
        'url': 'https://cdn/track.mp3',
        'cover_url': 'https://cdn/cover.jpg',
        'uploaded_by': 'u1',
        'created_at': '2026-01-15T10:00:00Z',
      });

      expect(model.id, 'm1');
      expect(model.title, 'Title');
      expect(model.artist, 'Artist');
      expect(model.album, 'Album');
      expect(model.duration, 185);
      expect(model.url, 'https://cdn/track.mp3');
      expect(model.coverUrl, 'https://cdn/cover.jpg');
      expect(model.uploadedBy, 'u1');
      expect(model.createdAt, DateTime.parse('2026-01-15T10:00:00Z'));
    });

    test('applique les valeurs par defaut quand des champs optionnels manquent', () {
      final model = MusicModel.fromJson({
        'id': 'm1',
        'title': 'Title',
        'url': 'https://cdn/track.mp3',
        'uploaded_by': 'u1',
        'created_at': '2026-01-15T10:00:00Z',
      });

      expect(model.artist, '');
      expect(model.album, '');
      expect(model.duration, 0);
      expect(model.coverUrl, isNull);
    });
  });

  test('formattedDuration ajoute un zero de padding sous 10 secondes', () {
    final model = MusicModel(
      id: 'm1',
      title: 't',
      artist: 'a',
      album: 'al',
      duration: 65,
      url: 'u',
      uploadedBy: 'u1',
      createdAt: DateTime(2026),
    );
    expect(model.formattedDuration, '1:05');
  });

  test('formattedDuration gere une duree nulle', () {
    final model = MusicModel(
      id: 'm1',
      title: 't',
      artist: 'a',
      album: 'al',
      duration: 0,
      url: 'u',
      uploadedBy: 'u1',
      createdAt: DateTime(2026),
    );
    expect(model.formattedDuration, '0:00');
  });

  test('formattedDuration gere plus d\'une heure', () {
    final model = MusicModel(
      id: 'm1',
      title: 't',
      artist: 'a',
      album: 'al',
      duration: 3725,
      url: 'u',
      uploadedBy: 'u1',
      createdAt: DateTime(2026),
    );
    expect(model.formattedDuration, '62:05');
  });
}
