import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('null est refuse', () {
      expect(Validators.email(null), 'Email is required');
    });

    test('chaine vide est refusee', () {
      expect(Validators.email(''), 'Email is required');
    });

    test('format invalide est refuse', () {
      expect(Validators.email('not-an-email'), 'Please enter a valid email address');
    });

    test('email valide est accepte', () {
      expect(Validators.email('alice@example.com'), isNull);
    });
  });

  group('Validators.password', () {
    test('null est refuse', () {
      expect(Validators.password(null), 'Password is required');
    });

    test('chaine vide est refusee', () {
      expect(Validators.password(''), 'Password is required');
    });

    test('moins de 8 caracteres est refuse', () {
      expect(Validators.password('short1'), 'Password must be at least 8 characters');
    });

    test('8 caracteres ou plus est accepte', () {
      expect(Validators.password('longenough'), isNull);
    });
  });

  group('Validators.confirmPassword', () {
    test('null est refuse', () {
      expect(Validators.confirmPassword(null, 'secret123'), 'Please confirm your password');
    });

    test('chaine vide est refusee', () {
      expect(Validators.confirmPassword('', 'secret123'), 'Please confirm your password');
    });

    test('valeur differente est refusee', () {
      expect(Validators.confirmPassword('other123', 'secret123'), 'Passwords do not match');
    });

    test('valeur identique est acceptee', () {
      expect(Validators.confirmPassword('secret123', 'secret123'), isNull);
    });
  });

  group('Validators.username', () {
    test('null est refuse', () {
      expect(Validators.username(null), 'Username is required');
    });

    test('chaine vide est refusee', () {
      expect(Validators.username(''), 'Username is required');
    });

    test('moins de 3 caracteres est refuse', () {
      expect(Validators.username('ab'), 'Username must be at least 3 characters');
    });

    test('plus de 30 caracteres est refuse', () {
      expect(Validators.username('a' * 31), 'Username must be at most 30 characters');
    });

    test('caracteres non alphanumeriques sont refuses', () {
      expect(
        Validators.username('alice!'),
        'Username can only contain letters, numbers, and underscores',
      );
    });

    test('lettres, chiffres et underscore sont acceptes', () {
      expect(Validators.username('alice_42'), isNull);
    });
  });
}
