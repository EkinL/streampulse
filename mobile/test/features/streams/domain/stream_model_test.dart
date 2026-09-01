import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/streams/domain/stream_model.dart';

void main() {
  group('StreamModel.fromJson', () {
    test('lit tous les champs fournis', () {
      final model = StreamModel.fromJson({
        'id': 's1',
        'title': 'Title',
        'description': 'Desc',
        'owner_id': 'u1',
        'status': 'live',
        'listener_count': 42,
        'format': 'aac',
        'created_at': '2026-01-15T10:00:00Z',
      });

      expect(model.id, 's1');
      expect(model.title, 'Title');
      expect(model.description, 'Desc');
      expect(model.ownerId, 'u1');
      expect(model.status, 'live');
      expect(model.listenerCount, 42);
      expect(model.format, 'aac');
      expect(model.createdAt, DateTime.parse('2026-01-15T10:00:00Z'));
    });

    test('applique les valeurs par defaut quand des champs optionnels manquent', () {
      final model = StreamModel.fromJson({
        'id': 's1',
        'title': 'Title',
        'owner_id': 'u1',
        'status': 'ended',
        'created_at': '2026-01-15T10:00:00Z',
      });

      expect(model.description, '');
      expect(model.listenerCount, 0);
      expect(model.format, 'mp3');
    });
  });

  group('isLive', () {
    test('vrai seulement pour le statut live', () {
      final live = StreamModel.fromJson({
        'id': 's1',
        'title': 't',
        'owner_id': 'u1',
        'status': 'live',
        'created_at': '2026-01-15T10:00:00Z',
      });
      final ended = live.copyWith(status: 'ended');

      expect(live.isLive, isTrue);
      expect(ended.isLive, isFalse);
    });
  });

  test('listenUrl construit le chemin SSE a partir de l\'id', () {
    final model = StreamModel.fromJson({
      'id': 'abc-123',
      'title': 't',
      'owner_id': 'u1',
      'status': 'live',
      'created_at': '2026-01-15T10:00:00Z',
    });
    expect(model.listenUrl, '/streams/abc-123/listen');
  });

  group('copyWith', () {
    final base = StreamModel.fromJson({
      'id': 's1',
      'title': 'Title',
      'owner_id': 'u1',
      'status': 'live',
      'listener_count': 3,
      'created_at': '2026-01-15T10:00:00Z',
    });

    test('sans argument conserve les valeurs', () {
      final copy = base.copyWith();
      expect(copy.id, base.id);
      expect(copy.title, base.title);
      expect(copy.listenerCount, base.listenerCount);
    });

    test('ne modifie que les champs fournis', () {
      final copy = base.copyWith(listenerCount: 10, status: 'ended');
      expect(copy.listenerCount, 10);
      expect(copy.status, 'ended');
      expect(copy.id, base.id);
      expect(copy.title, base.title);
      expect(copy.ownerId, base.ownerId);
      expect(copy.createdAt, base.createdAt);
    });
  });
}
