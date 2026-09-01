import 'package:flutter_riverpod/flutter_riverpod.dart' hide StreamNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/favorites/data/favorites_repository.dart';
import 'package:streampulse/features/streams/data/stream_repository.dart';
import 'package:streampulse/features/streams/domain/stream_model.dart';
import 'package:streampulse/features/streams/presentation/providers/stream_provider.dart';

class _MockStreamRepository extends Mock implements StreamRepository {}

class _MockFavoritesRepository extends Mock implements FavoritesRepository {}

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
  late _MockStreamRepository streamRepository;
  late _MockFavoritesRepository favoritesRepository;

  setUp(() {
    streamRepository = _MockStreamRepository();
    favoritesRepository = _MockFavoritesRepository();
  });

  StreamNotifier build() => StreamNotifier(streamRepository, favoritesRepository);

  test('fetchStreams declenche au demarrage et expose la liste en data', () async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1')]);

    final notifier = build();

    expect(notifier.state.isLoading, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.value, hasLength(1));
  });

  test('fetchStreams en erreur API : etat error avec le message du serveur', () async {
    when(() => streamRepository.listStreams())
        .thenThrow(const ApiException(message: 'boom', statusCode: 500));

    final notifier = build();
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.hasError, isTrue);
    expect(notifier.state.error, 'boom');
  });

  test('createStream rafraichit la liste apres succes', () async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => []);
    final notifier = build();
    await Future<void>.delayed(Duration.zero);

    when(() => streamRepository.createStream(
          title: 'New',
          description: 'Desc',
          format: 'mp3',
        )).thenAnswer((_) async => _stream('s1'));
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1')]);

    await notifier.createStream(title: 'New', description: 'Desc');

    expect(notifier.state.value, hasLength(1));
  });

  test('createStream propage l\'exception sans rafraichir', () async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => []);
    final notifier = build();
    await Future<void>.delayed(Duration.zero);

    when(() => streamRepository.createStream(
          title: 'New',
          description: 'Desc',
          format: 'mp3',
        )).thenThrow(const ApiException(message: 'boom'));

    await expectLater(
      () => notifier.createStream(title: 'New', description: 'Desc'),
      throwsA(isA<ApiException>()),
    );
    verify(() => streamRepository.listStreams()).called(1);
  });

  test('toggleFavorite appelle le repository de favoris', () async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => []);
    final notifier = build();
    await Future<void>.delayed(Duration.zero);

    when(() => favoritesRepository.addFavorite('s1')).thenAnswer((_) async {});

    await notifier.toggleFavorite('s1');

    verify(() => favoritesRepository.addFavorite('s1')).called(1);
  });

  test('toggleFavorite propage l\'exception', () async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => []);
    final notifier = build();
    await Future<void>.delayed(Duration.zero);

    when(() => favoritesRepository.addFavorite('s1'))
        .thenThrow(const ApiException(message: 'boom'));

    await expectLater(() => notifier.toggleFavorite('s1'), throwsA(isA<ApiException>()));
  });

  test('updateStream rafraichit la liste apres succes', () async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1')]);
    final notifier = build();
    await Future<void>.delayed(Duration.zero);

    when(() => streamRepository.updateStream(
          id: 's1',
          title: 'Updated',
          description: 'New desc',
        )).thenAnswer((_) async => _stream('s1'));
    when(() => streamRepository.listStreams()).thenAnswer((_) async => [_stream('s1'), _stream('s2')]);

    await notifier.updateStream(id: 's1', title: 'Updated', description: 'New desc');

    expect(notifier.state.value, hasLength(2));
  });

  test('updateStream propage l\'exception sans rafraichir', () async {
    when(() => streamRepository.listStreams()).thenAnswer((_) async => []);
    final notifier = build();
    await Future<void>.delayed(Duration.zero);

    when(() => streamRepository.updateStream(
          id: 's1',
          title: 'Updated',
          description: 'New desc',
        )).thenThrow(const ApiException(message: 'boom'));

    await expectLater(
      () => notifier.updateStream(id: 's1', title: 'Updated', description: 'New desc'),
      throwsA(isA<ApiException>()),
    );
    verify(() => streamRepository.listStreams()).called(1);
  });
}
