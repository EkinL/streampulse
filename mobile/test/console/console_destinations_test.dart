import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/console/presentation/widgets/console_shell.dart';

UserModel _user(String role) => UserModel(
      id: 'u1',
      email: 'user@example.com',
      username: 'user',
      role: role,
    );

void main() {
  group('destinationsFor', () {
    test('a listener gets no console section', () {
      expect(destinationsFor(_user('listener')), isEmpty);
    });

    test('a broadcaster gets broadcast only', () {
      final paths = destinationsFor(_user('broadcaster')).map((d) => d.path);
      expect(paths, ['/broadcaster']);
    });

    test('an admin gets both broadcast and users', () {
      final paths = destinationsFor(_user('admin')).map((d) => d.path);
      expect(paths, ['/broadcaster', '/admin']);
    });

    test('an unknown role is treated as a listener', () {
      expect(destinationsFor(_user('')), isEmpty);
      expect(destinationsFor(_user('moderator')), isEmpty);
    });
  });
}
