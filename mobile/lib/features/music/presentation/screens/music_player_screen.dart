import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../shared/providers/player_provider.dart';
import '../../../playlists/presentation/providers/playlist_provider.dart';
import '../providers/music_favorites_provider.dart';

class MusicPlayerScreen extends ConsumerWidget {
  const MusicPlayerScreen({super.key});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showAddToPlaylistSheet(BuildContext context, WidgetRef ref) {
    final playerState = ref.read(playerProvider);
    final track = playerState.currentTrack;
    if (track == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: SP.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Consumer(
        builder: (sheetCtx, sheetRef, _) {
          final playlistsAsync = sheetRef.watch(playlistListProvider);

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: SP.text3.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Add to Playlist',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: SP.text1,
                  ),
                ),
                const SizedBox(height: 16),
                // Create new playlist option
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: SP.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add, color: SP.btnText, size: 22),
                  ),
                  title: const Text(
                    'Create New Playlist',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: SP.text1,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _showCreatePlaylistAndAdd(context, ref, track.title, track.url, track.duration);
                  },
                ),
                const Divider(color: SP.divider, height: 1),
                // Existing playlists
                playlistsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(color: SP.accent),
                    ),
                  ),
                  error: (err, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Failed to load playlists',
                      style: TextStyle(color: SP.error),
                    ),
                  ),
                  data: (playlists) {
                    if (playlists.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No playlists yet. Create one above!',
                          style: TextStyle(color: SP.text3),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(sheetCtx).size.height * 0.3,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: playlists.length,
                        itemBuilder: (_, i) {
                          final playlist = playlists[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: SP.surfaceVariant,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.queue_music,
                                  color: SP.accent, size: 22),
                            ),
                            title: Text(
                              playlist.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: SP.text1,
                              ),
                            ),
                            subtitle: Text(
                              '${playlist.trackCount} tracks',
                              style: const TextStyle(
                                  fontSize: 12, color: SP.text3),
                            ),
                            onTap: () async {
                              Navigator.of(sheetCtx).pop();
                              try {
                                await ref
                                    .read(playlistListProvider.notifier)
                                    .addTrack(
                                      playlistId: playlist.id,
                                      title: track.title,
                                      url: track.url,
                                      duration: track.duration,
                                    );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Added to "${playlist.name}"'),
                                      backgroundColor: SP.surface,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to add: $e'),
                                      backgroundColor: SP.error,
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCreatePlaylistAndAdd(
    BuildContext context,
    WidgetRef ref,
    String trackTitle,
    String trackUrl,
    int trackDuration,
  ) {
    final nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SP.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'New Playlist',
          style: TextStyle(color: SP.text1, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Playlist name',
            filled: true,
            fillColor: SP.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          style: const TextStyle(color: SP.text1),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: SP.text3)),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx).pop();
              try {
                await ref
                    .read(playlistListProvider.notifier)
                    .create(name: name);
                // Fetch updated playlists and add the track to the new one
                final playlists =
                    ref.read(playlistListProvider).valueOrNull ?? [];
                if (playlists.isNotEmpty) {
                  final newPlaylist = playlists.last;
                  await ref.read(playlistListProvider.notifier).addTrack(
                        playlistId: newPlaylist.id,
                        title: trackTitle,
                        url: trackUrl,
                        duration: trackDuration,
                      );
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Created "$name" and added track'),
                      backgroundColor: SP.surface,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed: $e'),
                      backgroundColor: SP.error,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: SP.accent,
              foregroundColor: SP.btnText,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Create & Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final favorites = ref.watch(musicFavoritesProvider);
    final track = playerState.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: SP.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.music_off, size: 64, color: SP.text3),
              const SizedBox(height: 16),
              const Text(
                'No track playing',
                style: TextStyle(fontSize: 18, color: SP.text3),
              ),
              const SizedBox(height: 24),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_downward, color: SP.text1),
              ),
            ],
          ),
        ),
      );
    }

    final position = playerState.position;
    final duration = playerState.duration;
    final isPlaying = playerState.isPlaying;
    final sliderMax =
        duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final sliderValue =
        position.inMilliseconds.toDouble().clamp(0.0, sliderMax);

    return Scaffold(
      backgroundColor: SP.bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              SP.gradEnd.withOpacity(0.3),
              SP.bg,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: SP.text1, size: 28),
                      ),
                      const Text(
                        'Now Playing',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: SP.text2,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Builder(builder: (_) {
                            final isFav = favorites.contains(track.id);
                            return IconButton(
                              onPressed: () {
                                ref.read(musicFavoritesProvider.notifier).toggle(track.id);
                              },
                              icon: Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                color: isFav ? SP.liveBg : SP.text3,
                                size: 22,
                              ),
                            );
                          }),
                          IconButton(
                            onPressed: () =>
                                _showAddToPlaylistSheet(context, ref),
                            icon: const Icon(Icons.playlist_add,
                                color: SP.text2, size: 24),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Album art
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [SP.gradEnd, SP.accent],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SP.gradEnd.withOpacity(0.3),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.music_note,
                      color: SP.btnText, size: 80),
                ),

                const SizedBox(height: 48),

                // Track info
                Text(
                  track.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: SP.text1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  track.artist.isNotEmpty ? track.artist : 'Unknown artist',
                  style: const TextStyle(
                    fontSize: 16,
                    color: SP.text2,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Progress slider
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: SP.accent,
                    inactiveTrackColor: SP.surfaceVariant,
                    thumbColor: SP.accent,
                    overlayColor: SP.accent.withOpacity(0.1),
                    trackHeight: 4,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: sliderValue,
                    max: sliderMax,
                    onChanged: (value) {
                      ref
                          .read(playerProvider.notifier)
                          .seekTo(Duration(milliseconds: value.toInt()));
                    },
                  ),
                ),

                // Time labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(position),
                        style: const TextStyle(fontSize: 12, color: SP.text3),
                      ),
                      Text(
                        '-${_formatDuration(duration - position)}',
                        style: const TextStyle(fontSize: 12, color: SP.text3),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () =>
                          ref.read(playerProvider.notifier).previous(),
                      icon: const Icon(Icons.skip_previous,
                          color: SP.text1, size: 36),
                    ),
                    const SizedBox(width: 24),
                    GestureDetector(
                      onTap: () =>
                          ref.read(playerProvider.notifier).togglePlayPause(),
                      child: Icon(
                        isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: SP.accent,
                        size: 64,
                      ),
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      onPressed: () =>
                          ref.read(playerProvider.notifier).next(),
                      icon: const Icon(Icons.skip_next,
                          color: SP.text1, size: 36),
                    ),
                  ],
                ),

                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
