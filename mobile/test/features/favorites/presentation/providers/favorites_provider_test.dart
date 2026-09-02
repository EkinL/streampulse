import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';
import 'package:streampulse/features/favorites/data/favorites_repository.dart';
import 'package:streampulse/features/favorites/presentation/providers/favorites_provider.dart';
import 'package:streampulse/features/streams/domain/stream_model.dart';

class _MockFavoritesRepository extends Mock implements FavoritesRepository {}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAuthLocalSource extends Mock implements AuthLocalSource {}

/// Session posée par le test : le provider ne déclenche le fetch que pour
/// un compte connecté.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(AuthState initial)
      : super(_MockAuthRepository(), _MockAuthLocalSource()) {
    state = initial;
  }
}

const _me = UserModel(id: 'u1', email: 'a@a.fr', username: 'alice', role: 'user');

StreamModel _stream(String id) => StreamModel(
      id: id,
      title: 'Stream $id',
      description: '',
      ownerId: 'u1',
      status: 'live',
      listenerCount: 0,
      format: 'mp3',
      createdAt: DateTime(2026),
    );

void main() {
  late _MockFavoritesRepository repository;

  setUp(() {
    repository = _MockFavoritesRepository();
  });

  test('favoritesProvider construit un FavoritesNotifier branche sur le repository reel',
      () async {
    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1')]);
    final container = ProviderContainer(
      overrides: [
        favoritesRepositoryProvider.overrideWithValue(repository),
        authProvider.overrideWith((ref) =>
            _FakeAuthNotifier(const AuthAuthenticated(user: _me, token: 't'))),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(favoritesProvider.notifier), isA<FavoritesNotifier>());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(favoritesProvider).value, hasLength(1));
  });

  test('sans session, le provider reste vide et ne touche pas au reseau',
      () async {
    final container = ProviderContainer(
      overrides: [
        favoritesRepositoryProvider.overrideWithValue(repository),
        authProvider.overrideWith(
            (ref) => _FakeAuthNotifier(const AuthUnauthenticated())),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(favoritesProvider).value, isEmpty);
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => repository.listFavorites());
    expect(container.read(favoritesProvider).value, isEmpty);
  });

  test('fetch declenche au demarrage et expose la liste en data', () async {
    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1')]);

    final notifier = FavoritesNotifier(repository, enabled: true);

    expect(notifier.state.isLoading, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.value, hasLength(1));
    expect(notifier.state.value!.first.id, 's1');
  });

  test('fetch en erreur API : etat error avec le message du serveur', () async {
    when(() => repository.listFavorites())
        .thenThrow(const NotFoundException(message: 'no favorites'));

    final notifier = FavoritesNotifier(repository, enabled: true);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.hasError, isTrue);
    expect(notifier.state.error, 'no favorites');
  });

  test('add rafraichit la liste apres succes', () async {
    when(() => repository.listFavorites()).thenAnswer((_) async => []);
    final notifier = FavoritesNotifier(repository, enabled: true);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.addFavorite('s1')).thenAnswer((_) async {});
    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1')]);

    await notifier.add('s1');

    expect(notifier.state.value, hasLength(1));
  });

  test('add propage l\'exception sans rafraichir la liste', () async {
    when(() => repository.listFavorites()).thenAnswer((_) async => []);
    final notifier = FavoritesNotifier(repository, enabled: true);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.addFavorite('s1')).thenThrow(const ApiException(message: 'boom'));

    await expectLater(() => notifier.add('s1'), throwsA(isA<ApiException>()));
    verify(() => repository.listFavorites()).called(1);
  });

  test('remove rafraichit la liste apres succes', () async {
    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1')]);
    final notifier = FavoritesNotifier(repository, enabled: true);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.removeFavorite('s1')).thenAnswer((_) async {});
    when(() => repository.listFavorites()).thenAnswer((_) async => []);

    await notifier.remove('s1');

    expect(notifier.state.value, isEmpty);
  });

  test('remove propage l\'exception sans rafraichir la liste', () async {
    when(() => repository.listFavorites()).thenAnswer((_) async => [_stream('s1')]);
    final notifier = FavoritesNotifier(repository, enabled: true);
    await Future<void>.delayed(Duration.zero);

    when(() => repository.removeFavorite('s1')).thenThrow(const ApiException(message: 'boom'));

    await expectLater(() => notifier.remove('s1'), throwsA(isA<ApiException>()));
    verify(() => repository.listFavorites()).called(1);
  });
}
