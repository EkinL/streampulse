import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/favorites_repository.dart';
import '../../../auth/domain/auth_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../streams/domain/stream_model.dart';
import '../../../../core/network/api_exceptions.dart';

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, AsyncValue<List<StreamModel>>>(
        (ref) {
  // Sans session, pas d'appel réseau : l'endpoint répondrait 401. Le
  // notifier est recréé à chaque changement de connexion, ce qui recharge
  // les favoris au login et les vide au logout.
  final isAuthenticated =
      ref.watch(authProvider.select((s) => s is AuthAuthenticated));
  return FavoritesNotifier(
    ref.read(favoritesRepositoryProvider),
    enabled: isAuthenticated,
  );
});

/// IDs des flux favoris de l'utilisateur, dérivés de [favoritesProvider].
/// Permet à n'importe quel écran (Direct, Détail…) de savoir si un flux est
/// déjà suivi sans dupliquer sa propre requête réseau.
final favoriteIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(favoritesProvider).maybeWhen(
        data: (streams) => streams.map((s) => s.id).toSet(),
        orElse: () => const {},
      );
});

class FavoritesNotifier
    extends StateNotifier<AsyncValue<List<StreamModel>>> {
  final FavoritesRepository _repository;
  final bool enabled;

  FavoritesNotifier(this._repository, {required this.enabled})
      : super(const AsyncValue.data([])) {
    if (enabled) fetch();
  }

  Future<void> fetch() async {
    if (!enabled) return;
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
