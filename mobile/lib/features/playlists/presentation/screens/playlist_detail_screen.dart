import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../domain/playlist_model.dart';
import '../providers/playlist_provider.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/error_widget.dart' as app_error;
import '../../../../core/utils/extensions.dart';
import '../../../music/data/music_repository.dart';
import '../../../music/domain/music_model.dart';
import '../../../../shared/providers/player_provider.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistAsync = ref.watch(playlistDetailProvider(playlistId));

    return Scaffold(
      backgroundColor: SP.bg,
      appBar: AppBar(
        backgroundColor: SP.surface,
        foregroundColor: SP.text1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Playlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Ajouter un morceau',
            onPressed: () => _showAddTrackDialog(context, ref),
          ),
        ],
      ),
      body: playlistAsync.when(
        loading: () => const LoadingIndicator(),
        error: (error, _) => app_error.AppErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(playlistDetailProvider(playlistId)),
        ),
        data: (playlist) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        SP.accent.withValues(alpha: 0.2),
                        SP.accent.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: SP.tag,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.queue_music, color: SP.accent, size: 26),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  playlist.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5,
                                    color: SP.text1,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: SP.accent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        playlist.isPublic ? Icons.public : Icons.lock,
                                        size: 12,
                                        color: SP.accent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        playlist.isPublic ? 'Public' : 'Privé',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: SP.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${playlist.trackCount} titre${playlist.trackCount != 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 13, color: SP.text2),
                      ),
                      if (playlist.tracks.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () {
                            final musicList = playlist.tracks
                                .map((track) => MusicModel(
                                      id: track.id,
                                      title: track.title,
                                      artist: '',
                                      album: '',
                                      duration: track.duration,
                                      url: track.url,
                                      coverUrl: null,
                                      uploadedBy: '',
                                      createdAt: DateTime.now(),
                                    ))
                                .toList();
                            ref
                                .read(playerProvider.notifier)
                                .playPlaylist(musicList, 0);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: SP.primaryGradient,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow, color: SP.btnText, size: 20),
                                SizedBox(width: 6),
                                Text(
                                  'Tout écouter',
                                  style: TextStyle(
                                    color: SP.btnText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (playlist.tracks.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Titres',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: SP.text1),
                  ),
                ),
              Expanded(
                child: playlist.tracks.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.queue_music,
                              size: 80,
                              color: SP.text3,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Aucun titre pour l\'instant',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SP.text2),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Touchez + pour ajouter un titre',
                              style: TextStyle(fontSize: 13, color: SP.text3),
                            ),
                          ],
                        ),
                      )
                    : _ReorderableTrackList(
                        playlistId: playlistId,
                        tracks: playlist.tracks,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddTrackDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SP.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => _AddTrackSheet(
          playlistId: playlistId,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

/// The track list keeps its own copy of the tracks so a drag & drop feels
/// instant: we reorder locally first, then persist through the API, and only
/// roll back if the server refuses. The provider refetch (add/remove/pull to
/// refresh) re-seeds the local copy via [didUpdateWidget].
class _ReorderableTrackList extends ConsumerStatefulWidget {
  final String playlistId;
  final List<TrackModel> tracks;

  const _ReorderableTrackList({
    required this.playlistId,
    required this.tracks,
  });

  @override
  ConsumerState<_ReorderableTrackList> createState() =>
      _ReorderableTrackListState();
}

class _ReorderableTrackListState extends ConsumerState<_ReorderableTrackList> {
  late List<TrackModel> _tracks;

  @override
  void initState() {
    super.initState();
    _tracks = List.of(widget.tracks);
  }

  @override
  void didUpdateWidget(covariant _ReorderableTrackList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tracks, widget.tracks)) {
      _tracks = List.of(widget.tracks);
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    // ReorderableListView quirk: when an item moves down, newIndex is
    // computed as if the dragged item was already removed from the list.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;

    final previous = List.of(_tracks);
    setState(() {
      final track = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, track);
    });

    try {
      await ref.read(playlistListProvider.notifier).reorderTracks(
            playlistId: widget.playlistId,
            trackIds: _tracks.map((t) => t.id).toList(),
          );
      ref.invalidate(playlistDetailProvider(widget.playlistId));
    } catch (_) {
      // The server refused: put things back the way they were.
      if (!mounted) return;
      setState(() => _tracks = previous);
      context.showSnackBar('Impossible de réordonner les titres');
    }
  }

  void _playFrom(int index) {
    final musicList = _tracks
        .map((t) => MusicModel(
              id: t.id,
              title: t.title,
              artist: '',
              album: '',
              duration: t.duration,
              url: t.url,
              coverUrl: null,
              uploadedBy: '',
              createdAt: DateTime.now(),
            ))
        .toList();
    ref.read(playerProvider.notifier).playPlaylist(musicList, index);
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: _tracks.length,
      onReorder: _onReorder,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        return _TrackListItem(
          key: ValueKey(track.id),
          track: track,
          index: index,
          onTap: () => _playFrom(index),
          onRemove: () {
            ref
                .read(playlistListProvider.notifier)
                .removeTrack(
                  playlistId: widget.playlistId,
                  trackId: track.id,
                )
                .then((_) {
              if (!context.mounted) return;
              ref.invalidate(playlistDetailProvider(widget.playlistId));
              context.showSnackBar('Titre retiré');
            });
          },
        );
      },
    );
  }
}

class _TrackListItem extends StatelessWidget {
  final TrackModel track;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  const _TrackListItem({
    super.key,
    required this.track,
    required this.index,
    required this.onRemove,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: SP.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: SP.tag,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${index + 1}',
            style: const TextStyle(color: SP.accent, fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SP.text1),
        ),
        subtitle: Text(
          track.formattedDuration,
          style: const TextStyle(fontSize: 12, color: SP.text3),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Retirer',
              icon: const Icon(Icons.remove_circle_outline, color: SP.error),
              onPressed: onRemove,
            ),
            const Icon(Icons.drag_handle, color: SP.text3),
          ],
        ),
      ),
    );
  }
}

class _AddTrackSheet extends ConsumerStatefulWidget {
  final String playlistId;
  final ScrollController scrollController;

  const _AddTrackSheet({
    required this.playlistId,
    required this.scrollController,
  });

  @override
  ConsumerState<_AddTrackSheet> createState() => _AddTrackSheetState();
}

class _AddTrackSheetState extends ConsumerState<_AddTrackSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<MusicModel> _results = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(musicRepositoryProvider);
      final results = await repo.searchMusic(query.trim());
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 16),
          decoration: BoxDecoration(
            color: SP.text3.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Ajouter un titre',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: SP.text1,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: SP.text1, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Rechercher dans le catalogue…',
              hintStyle: const TextStyle(color: SP.text3, fontSize: 14),
              filled: true,
              fillColor: SP.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              prefixIcon:
                  const Icon(Icons.search, color: SP.text3, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon:
                          const Icon(Icons.clear, color: SP.text3, size: 20),
                      tooltip: 'Effacer',
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        const SizedBox(height: 12),
        // Results
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: SP.accent))
              : _results.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.isEmpty
                            ? 'Recherchez un titre à ajouter'
                            : 'Aucun résultat',
                        style: const TextStyle(color: SP.text3, fontSize: 14),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final music = _results[index];
                        return _SearchResultTile(
                          music: music,
                          onAdd: () {
                            ref
                                .read(playlistListProvider.notifier)
                                .addTrack(
                                  playlistId: widget.playlistId,
                                  title: music.title,
                                  url: music.url,
                                  duration: music.duration,
                                );
                            Navigator.of(context).pop();
                            ref.invalidate(
                                playlistDetailProvider(widget.playlistId));
                            context.showSnackBar('Titre ajouté');
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final MusicModel music;
  final VoidCallback onAdd;

  const _SearchResultTile({required this.music, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SP.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [SP.gradEnd, SP.accent],
              ),
            ),
            child: const Icon(Icons.music_note, color: SP.btnText, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  music.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SP.text1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  music.artist.isNotEmpty ? music.artist : 'Artiste inconnu',
                  style: const TextStyle(fontSize: 12, color: SP.text2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            music.formattedDuration,
            style: const TextStyle(fontSize: 12, color: SP.text3),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onAdd,
            tooltip: 'Ajouter à la playlist',
            icon: const Icon(Icons.add_circle, color: SP.accent, size: 28),
          ),
        ],
      ),
    );
  }
}
