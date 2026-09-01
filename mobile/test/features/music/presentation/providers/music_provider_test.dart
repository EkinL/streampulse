import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:streampulse/features/music/data/music_repository.dart';
import 'package:streampulse/features/music/domain/music_model.dart';
import 'package:streampulse/features/music/presentation/providers/music_provider.dart';

class _MockMusicRepository extends Mock implements MusicRepository {}

MusicModel _track(String id) => MusicModel(
      id: id,
      title: 'Track $id',
      artist: 'Artist',
      album: 'Album',
      duration: 120,
      url: 'https://cdn/$id.mp3',
      uploadedBy: 'u1',
      createdAt: DateTime(2026),
    );

void main() {
  late _MockMusicRepository repository;

  setUp(() {
    repository = _MockMusicRepository();
  });

  test('musicListProvider construit un MusicNotifier branche sur le repository reel', () async {
    when(() => repository.listMusic()).thenAnswer((_) async => [_track('m1')]);
    final container = ProviderContainer(
      overrides: [musicRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    expect(container.read(musicListProvider.notifier), isA<MusicNotifier>());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(musicListProvider).value, hasLength(1));
  });

  test('fetch declenche au demarrage et expose la liste en data', () async {
    when(() => repository.listMusic()).thenAnswer((_) async => [_track('m1')]);

    final notifier = MusicNotifier(repository);

    expect(notifier.state.isLoading, isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.value, hasLength(1));
  });

  test('fetch en erreur : etat error', () async {
    when(() => repository.listMusic()).thenThrow(Exception('boom'));

    final notifier = MusicNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.hasError, isTrue);
  });

  test('search avec une requete vide retombe sur la liste complete', () async {
    when(() => repository.listMusic()).thenAnswer((_) async => [_track('m1'), _track('m2')]);
    final notifier = MusicNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    await notifier.search('   ');

    expect(notifier.state.value, hasLength(2));
    verify(() => repository.listMusic()).called(2);
  });

  test('search avec une requete non vide appelle searchMusic', () async {
    when(() => repository.listMusic()).thenAnswer((_) async => []);
    when(() => repository.searchMusic('daft')).thenAnswer((_) async => [_track('m1')]);
    final notifier = MusicNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    await notifier.search('daft');

    expect(notifier.state.value, hasLength(1));
    expect(notifier.state.value!.first.id, 'm1');
  });

  test('search en erreur : etat error', () async {
    when(() => repository.listMusic()).thenAnswer((_) async => []);
    when(() => repository.searchMusic('daft')).thenThrow(Exception('boom'));
    final notifier = MusicNotifier(repository);
    await Future<void>.delayed(Duration.zero);

    await notifier.search('daft');

    expect(notifier.state.hasError, isTrue);
  });
}
