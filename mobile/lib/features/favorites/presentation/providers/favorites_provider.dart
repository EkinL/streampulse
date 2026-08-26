import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/favorites_repository.dart';
import '../../../streams/domain/stream_model.dart';
import '../../../../core/network/api_exceptions.dart';

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, AsyncValue<List<StreamModel>>>(
        (ref) {
  return FavoritesNotifier(ref.read(favoritesRepositoryProvider));
});

class FavoritesNotifier
    extends StateNotifier<AsyncValue<List<StreamModel>>> {
  final FavoritesRepository _repository;

  FavoritesNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    try {
      final favorites = await _repository.listFavorites();
      state = AsyncValue.data(favorites);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error(e.toString(), st);
    }
  }

  Future<void> add(String streamId) async {
    try {
      await _repository.addFavorite(streamId);
      await fetch();
    } on ApiException {
      rethrow;
    }
  }

  Future<void> remove(String streamId) async {
    try {
      await _repository.removeFavorite(streamId);
      await fetch();
    } on ApiException {
      rethrow;
    }
  }
}
