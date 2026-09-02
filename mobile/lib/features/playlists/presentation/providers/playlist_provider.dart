import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/playlist_repository.dart';
import '../../domain/playlist_model.dart';
import '../../../../core/network/api_exceptions.dart';

final playlistListProvider =
    StateNotifierProvider<PlaylistNotifier, AsyncValue<List<PlaylistModel>>>(
        (ref) {
  return PlaylistNotifier(ref.read(playlistRepositoryProvider));
});

/// autoDispose : sans lui la reponse restait en cache pour toute la session,
/// et un ajout fait depuis un autre ecran (lecteur) n'apparaissait jamais ici.
final playlistDetailProvider =
    FutureProvider.autoDispose.family<PlaylistModel, String>((ref, id) async {
  final repo = ref.read(playlistRepositoryProvider);
  return repo.getPlaylist(id);
});

final publicPlaylistListProvider = StateNotifierProvider<
    PublicPlaylistNotifier, AsyncValue<List<PlaylistModel>>>((ref) {
  return PublicPlaylistNotifier(ref.read(playlistRepositoryProvider));
});

/// Read-only: public playlists belong to other users, so there's nothing to
/// create/update/delete from here (see [PlaylistNotifier] for that).
class PublicPlaylistNotifier
    extends StateNotifier<AsyncValue<List<PlaylistModel>>> {
  final PlaylistRepository _repository;

  PublicPlaylistNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    try {
      final playlists = await _repository.listPublicPlaylists();
      state = AsyncValue.data(playlists);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error(e.toString(), st);
    }
  }
}

class PlaylistNotifier
    extends StateNotifier<AsyncValue<List<PlaylistModel>>> {
  final PlaylistRepository _repository;

  PlaylistNotifier(this._repository)
      : super(const AsyncValue.loading()) {
    fetch();
  }

  Future<void> fetch() async {
    state = const AsyncValue.loading();
    try {
      final playlists = await _repository.listPlaylists();
      state = AsyncValue.data(playlists);
    } on ApiException catch (e, st) {
      state = AsyncValue.error(e.message, st);
    } catch (e, st) {
      state = AsyncValue.error(e.toString(), st);
    }
  }

  Future<void> create({
    required String name,
    bool isPublic = false,
  }) async {
    try {
      await _repository.createPlaylist(name: name, isPublic: isPublic);
      await fetch();
    } on ApiException {
      rethrow;
    }
  }

  Future<void> update({
    required String id,
    String? name,
    bool? isPublic,
  }) async {
    try {
      await _repository.updatePlaylist(
        id: id,
        name: name,
        isPublic: isPublic,
      );
      await fetch();
    } on ApiException {
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    try {
      await _repository.deletePlaylist(id);
      await fetch();
    } on ApiException {
      rethrow;
    }
  }

  Future<void> addTrack({
    required String playlistId,
    required String title,
    required String url,
    required int duration,
  }) async {
    try {
      await _repository.addTrack(
        playlistId: playlistId,
        title: title,
        url: url,
        duration: duration,
      );
      await fetch();
    } on ApiException {
      rethrow;
    }
  }

  Future<void> reorderTracks({
    required String playlistId,
    required List<String> trackIds,
  }) async {
    try {
      await _repository.reorderTracks(
        playlistId: playlistId,
        trackIds: trackIds,
      );
      // No fetch() here: the order doesn't change anything on the list
      // screen (names/counts), only the detail screen cares.
    } on ApiException {
      rethrow;
    }
  }

  Future<void> removeTrack({
    required String playlistId,
    required String trackId,
  }) async {
    try {
      await _repository.removeTrack(
        playlistId: playlistId,
        trackId: trackId,
      );
      await fetch();
    } on ApiException {
      rethrow;
    }
  }
}
