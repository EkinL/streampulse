import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/admin/presentation/screens/admin_users_screen.dart';

void main() {
  group('assignableRoles', () {
    test('matches the roles the API accepts', () {
      // domain.Role in the backend: anonymous, user, broadcaster, admin.
      // 'anonymous' is not assignable to an account.
      expect(assignableRoles, ['user', 'broadcaster', 'admin']);
      expect(assignableRoles, isNot(contains('listener')));
    });
  });

  group('roleOptionsFor', () {
    test('leaves a known role list untouched', () {
      expect(roleOptionsFor('user'), assignableRoles);
      expect(roleOptionsFor('admin'), assignableRoles);
    });

    test('includes an unknown current role so the dropdown never asserts', () {
      final options = roleOptionsFor('moderator');
      expect(options, containsAll(assignableRoles));
      expect(options, contains('moderator'));
      expect(options.where((r) => r == 'moderator').length, 1);
    });
  });

  group('roleLabel', () {
    test('shows a plain account as Listener', () {
      expect(roleLabel('user'), 'Listener');
    });

    test('falls back to the raw value for anything unexpected', () {
      expect(roleLabel('moderator'), 'moderator');
    });
  });
}
