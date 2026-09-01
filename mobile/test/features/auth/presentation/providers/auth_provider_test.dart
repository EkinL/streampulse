import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthLocalSource extends Mock implements AuthLocalSource {}

void main() {
  late _MockAuthRepository repository;
  late _MockAuthLocalSource localSource;
  late AuthNotifier notifier;

  Map<String, dynamic> tokenResponse({String access = 'access-1', String refresh = 'refresh-1'}) => {
        'access_token': access,
        'refresh_token': refresh,
        'user': {
          'id': 'u1',
          'email': 'a@example.com',
          'username': 'alice',
          'role': 'listener',
        },
      };

  setUp(() {
    repository = _MockAuthRepository();
    localSource = _MockAuthLocalSource();
    when(() => localSource.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        )).thenAnswer((_) async {});
    when(() => localSource.clearTokens()).thenAnswer((_) async {});
    notifier = AuthNotifier(repository, localSource);
  });

  tearDown(() => notifier.dispose());

  test('l\'etat initial est AuthLoading', () {
    expect(notifier.state, isA<AuthLoading>());
  });

  group('checkAuth', () {
    test('sans jeton d\'acces : Unauthenticated', () async {
      when(() => localSource.getAccessToken()).thenAnswer((_) async => null);

      await notifier.checkAuth();

      expect(notifier.state, isA<AuthUnauthenticated>());
    });

    test('jeton d\'acces vide : Unauthenticated', () async {
      when(() => localSource.getAccessToken()).thenAnswer((_) async => '');

      await notifier.checkAuth();

      expect(notifier.state, isA<AuthUnauthenticated>());
    });

    test('jeton d\'acces sans refresh token : Unauthenticated', () async {
      when(() => localSource.getAccessToken()).thenAnswer((_) async => 'access-1');
      when(() => localSource.getRefreshToken()).thenAnswer((_) async => null);

      await notifier.checkAuth();

      expect(notifier.state, isA<AuthUnauthenticated>());
    });

    test('refresh reussi : Authenticated et nouveaux jetons sauvegardes', () async {
      when(() => localSource.getAccessToken()).thenAnswer((_) async => 'access-1');
      when(() => localSource.getRefreshToken()).thenAnswer((_) async => 'refresh-1');
      when(() => repository.refreshToken('refresh-1'))
          .thenAnswer((_) async => tokenResponse(access: 'new-access', refresh: 'new-refresh'));

      await notifier.checkAuth();

      final state = notifier.state;
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).token, 'new-access');
      expect(state.user.id, 'u1');
      verify(() => localSource.saveTokens(accessToken: 'new-access', refreshToken: 'new-refresh'))
          .called(1);
    });

    test('refresh rejete : jetons effaces et Unauthenticated', () async {
      when(() => localSource.getAccessToken()).thenAnswer((_) async => 'access-1');
      when(() => localSource.getRefreshToken()).thenAnswer((_) async => 'refresh-1');
      when(() => repository.refreshToken('refresh-1'))
          .thenThrow(const UnauthorizedException());

      await notifier.checkAuth();

      expect(notifier.state, isA<AuthUnauthenticated>());
      verify(() => localSource.clearTokens()).called(1);
    });

    test('erreur inattendue en lisant le stockage : Unauthenticated', () async {
      when(() => localSource.getAccessToken()).thenThrow(Exception('boom'));

      await notifier.checkAuth();

      expect(notifier.state, isA<AuthUnauthenticated>());
    });
  });

  group('login', () {
    test('succes : Authenticated et jetons sauvegardes', () async {
      when(() => repository.login(email: 'a@example.com', password: 'secret'))
          .thenAnswer((_) async => tokenResponse());

      await notifier.login(email: 'a@example.com', password: 'secret');

      final state = notifier.state;
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.email, 'a@example.com');
      verify(() => localSource.saveTokens(accessToken: 'access-1', refreshToken: 'refresh-1'))
          .called(1);
    });

    test('ApiException : AuthError avec le message du serveur', () async {
      when(() => repository.login(email: 'a@example.com', password: 'wrong'))
          .thenThrow(const ApiException(message: 'Invalid credentials', statusCode: 401));

      await notifier.login(email: 'a@example.com', password: 'wrong');

      final state = notifier.state;
      expect(state, isA<AuthError>());
      expect((state as AuthError).message, 'Invalid credentials');
    });

    test('erreur inattendue : AuthError avec la representation de l\'erreur', () async {
      when(() => repository.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(Exception('network down'));

      await notifier.login(email: 'a@example.com', password: 'secret');

      expect(notifier.state, isA<AuthError>());
    });
  });

  group('register', () {
    test('succes : Authenticated et jetons sauvegardes', () async {
      when(() => repository.register(
            username: 'alice',
            email: 'a@example.com',
            password: 'secret',
            acceptedTerms: true,
          )).thenAnswer((_) async => tokenResponse());

      await notifier.register(
        username: 'alice',
        email: 'a@example.com',
        password: 'secret',
        acceptedTerms: true,
      );

      expect(notifier.state, isA<AuthAuthenticated>());
    });

    test('ApiException : AuthError avec le message du serveur', () async {
      when(() => repository.register(
            username: 'alice',
            email: 'a@example.com',
            password: 'secret',
            acceptedTerms: true,
          )).thenThrow(const ApiException(message: 'Email already used', statusCode: 409));

      await notifier.register(
        username: 'alice',
        email: 'a@example.com',
        password: 'secret',
        acceptedTerms: true,
      );

      final state = notifier.state;
      expect(state, isA<AuthError>());
      expect((state as AuthError).message, 'Email already used');
    });
  });

  test('logout efface les jetons et repasse a Unauthenticated', () async {
    await notifier.logout();

    expect(notifier.state, isA<AuthUnauthenticated>());
    verify(() => localSource.clearTokens()).called(1);
  });

  group('deleteAccount', () {
    test('succes : jetons effaces et Unauthenticated', () async {
      when(() => repository.deleteAccount()).thenAnswer((_) async {});

      await notifier.deleteAccount();

      expect(notifier.state, isA<AuthUnauthenticated>());
      verify(() => localSource.clearTokens()).called(1);
    });

    test('404 (compte deja supprime) : traite comme un succes', () async {
      when(() => repository.deleteAccount()).thenThrow(const NotFoundException());

      await notifier.deleteAccount();

      expect(notifier.state, isA<AuthUnauthenticated>());
      verify(() => localSource.clearTokens()).called(1);
    });

    test('401 (session expiree) : traite comme un succes', () async {
      when(() => repository.deleteAccount()).thenThrow(const UnauthorizedException());

      await notifier.deleteAccount();

      expect(notifier.state, isA<AuthUnauthenticated>());
      verify(() => localSource.clearTokens()).called(1);
    });

    test('autre erreur : propagee, la session locale reste ouverte', () async {
      when(() => repository.deleteAccount())
          .thenThrow(const ApiException(message: 'boom', statusCode: 500));

      await expectLater(() => notifier.deleteAccount(), throwsA(isA<ApiException>()));

      verifyNever(() => localSource.clearTokens());
    });
  });
}
