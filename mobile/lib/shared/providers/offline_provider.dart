import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/constants.dart';
import '../../core/storage/offline_audio_store.dart';

class OfflineState {
  /// Pistes telechargees, ecoutables sans reseau.
  final Set<String> cachedIds;

  /// Pistes en cours de telechargement.
  final Set<String> downloadingIds;

  const OfflineState({
    this.cachedIds = const {},
    this.downloadingIds = const {},
  });

  bool isCached(String trackId) => cachedIds.contains(trackId);
  bool isDownloading(String trackId) => downloadingIds.contains(trackId);

  OfflineState copyWith({Set<String>? cachedIds, Set<String>? downloadingIds}) {
    return OfflineState(
      cachedIds: cachedIds ?? this.cachedIds,
      downloadingIds: downloadingIds ?? this.downloadingIds,
    );
  }
}

/// Mode offline : telechargement des morceaux de playlists sur le disque
/// pour une ecoute sans reseau. Indisponible sur le web (pas de systeme de
/// fichiers), ou toutes les operations sont des no-op.
class OfflineNotifier extends StateNotifier<OfflineState> {
  final OfflineAudioStore _store;
  final Dio _dio;

  OfflineNotifier(this._store, this._dio) : super(const OfflineState()) {
    if (!kIsWeb) _restore();
  }

  Future<void> _restore() async {
    try {
      final ids = await _store.cachedTrackIds();
      if (mounted) state = state.copyWith(cachedIds: ids);
    } catch (e) {
      debugPrint('offline: scan du cache impossible: $e');
    }
  }

  String _resolveUrl(String url) {
    if (url.startsWith('/')) {
      return '${AppConstants.apiBaseUrl}$url';
    }
    return url;
  }

  /// Telecharge une piste. Idempotent : deja en cache ou en cours -> no-op.
  Future<void> downloadTrack({required String id, required String url}) async {
    if (kIsWeb || state.isCached(id) || state.isDownloading(id)) return;

    state = state.copyWith(downloadingIds: {...state.downloadingIds, id});
    try {
      final partFile = await _store.partFileFor(id, url);
      await _dio.download(_resolveUrl(url), partFile.path);
      await _store.commit(partFile);
      if (mounted) {
        state = state.copyWith(cachedIds: {...state.cachedIds, id});
      }
    } catch (e) {
      debugPrint('offline: echec du telechargement de $id: $e');
      rethrow;
    } finally {
      if (mounted) {
        state = state.copyWith(
          downloadingIds: {...state.downloadingIds}..remove(id),
        );
      }
    }
  }

  /// Telecharge toutes les pistes d'une playlist (sequentiel, volontairement :
  /// pas de rafale de connexions sur un reseau mobile). Renvoie le nombre de
  /// pistes qui ont echoue.
  Future<int> downloadTracks(List<({String id, String url})> tracks) async {
    var failures = 0;
    for (final track in tracks) {
      try {
        await downloadTrack(id: track.id, url: track.url);
      } catch (_) {
        failures++;
      }
    }
    return failures;
  }

  Future<void> removeTrack(String trackId) async {
    if (kIsWeb) return;
    await _store.delete(trackId);
    if (mounted) {
      state = state.copyWith(cachedIds: {...state.cachedIds}..remove(trackId));
    }
  }

  Future<void> removeTracks(Iterable<String> trackIds) async {
    for (final id in trackIds) {
      await removeTrack(id);
    }
  }

  /// Chemin local de la piste si elle est telechargee, sinon null.
  /// Utilise par le lecteur pour jouer le fichier local en priorite.
  Future<String?> localPathFor(String trackId) async {
    if (kIsWeb || !state.isCached(trackId)) return null;
    return _store.localPathFor(trackId);
  }
}

final offlineAudioStoreProvider = Provider<OfflineAudioStore>((ref) {
  return OfflineAudioStore();
});

final offlineProvider =
    StateNotifierProvider<OfflineNotifier, OfflineState>((ref) {
  // Dio dedie (sans le LogInterceptor de l'API qui tracerait les octets
  // audio) : les fichiers /uploads sont publics, pas besoin d'auth.
  return OfflineNotifier(ref.watch(offlineAudioStoreProvider), Dio());
});
