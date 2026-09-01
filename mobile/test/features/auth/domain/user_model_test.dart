import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';

void main() {
  const listener = UserModel(
    id: 'u1',
    email: 'listener@example.com',
    username: 'listener',
    role: 'listener',
  );

  group('fromJson / toJson', () {
    test('reconstruit un UserModel a partir du JSON API', () {
      final user = UserModel.fromJson({
        'id': 'u1',
        'email': 'listener@example.com',
        'username': 'listener',
        'role': 'listener',
      });

      expect(user, isA<UserModel>());
      expect(user.id, 'u1');
      expect(user.email, 'listener@example.com');
      expect(user.username, 'listener');
      expect(user.role, 'listener');
    });

    test('serialise vers un JSON symetrique', () {
      expect(listener.toJson(), {
        'id': 'u1',
        'email': 'listener@example.com',
        'username': 'listener',
        'role': 'listener',
      });
    });
  });

  group('roles', () {
    test('isAdmin est vrai seulement pour le role admin', () {
      expect(listener.isAdmin, isFalse);
      expect(listener.copyWith(role: 'admin').isAdmin, isTrue);
    });

    test('isBroadcaster est vrai pour broadcaster et pour admin', () {
      expect(listener.isBroadcaster, isFalse);
      expect(listener.copyWith(role: 'broadcaster').isBroadcaster, isTrue);
      expect(listener.copyWith(role: 'admin').isBroadcaster, isTrue);
    });
  });

  group('copyWith', () {
    test('sans argument renvoie les memes valeurs', () {
      final copy = listener.copyWith();
      expect(copy.id, listener.id);
      expect(copy.email, listener.email);
      expect(copy.username, listener.username);
      expect(copy.role, listener.role);
    });

    test('ne modifie que les champs fournis', () {
      final copy = listener.copyWith(role: 'broadcaster');
      expect(copy.role, 'broadcaster');
      expect(copy.id, listener.id);
      expect(copy.email, listener.email);
      expect(copy.username, listener.username);
    });
  });
}
