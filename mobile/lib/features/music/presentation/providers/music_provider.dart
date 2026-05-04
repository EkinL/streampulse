import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/music_repository.dart';
import '../../domain/music_model.dart';

class MusicNotifier extends StateNotifier<AsyncValue<List<MusicModel>>> {
  final MusicRepository _repository;

  MusicNotifier(this._repository) : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    try {
      final music = await _repository.listMusic();
      state = AsyncValue.data(music);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      return fetch();
    }
    state = const AsyncValue.loading();
    try {
      final results = await _repository.searchMusic(query);
      state = AsyncValue.data(results);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final musicListProvider =
    StateNotifierProvider<MusicNotifier, AsyncValue<List<MusicModel>>>((ref) {
  return MusicNotifier(ref.read(musicRepositoryProvider));
});
