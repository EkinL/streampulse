import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../providers/playlist_provider.dart';
import '../widgets/playlist_tile.dart';
import '../../../../core/utils/extensions.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistListProvider);

    return Scaffold(
      backgroundColor: context.colors.altBg,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.text1,
        title: const Text('Playlists'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Center(
              child: playlistsAsync.maybeWhen(
                data: (playlists) => Text(
                  '${playlists.length} liste${playlists.length != 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.colors.text3),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: context.colors.accent,
        onRefresh: () async {
          await ref.read(playlistListProvider.notifier).fetch();
        },
        child: playlistsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: context.colors.accent)),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: $error', style: TextStyle(color: context.colors.text2)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    ref.read(playlistListProvider.notifier).fetch();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (playlists) {
            if (playlists.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.queue_music,
                      size: 80,
                      color: context.colors.text3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No playlists yet',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: context.colors.text3,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create your first playlist',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.colors.text3,
                              ),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return PlaylistTile(
                  playlist: playlist,
                  onTap: () => context.push('/playlists/${playlist.id}'),
                  onDelete: () {
                    _showDeleteConfirmation(context, ref, playlist.id);
                  },
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FloatingActionButton(
          backgroundColor: context.colors.accent,
          foregroundColor: SP.btnText,
          onPressed: () => _showCreateDialog(context, ref),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    bool isPublic = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: context.colors.surface,
          title: Text('Create Playlist', style: TextStyle(color: context.colors.text1)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Playlist name',
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text('Public', style: TextStyle(color: context.colors.text1)),
                value: isPublic,
                activeThumbColor: context.colors.accent,
                onChanged: (v) => setDialogState(() => isPublic = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Cancel', style: TextStyle(color: context.colors.text3)),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  ref.read(playlistListProvider.notifier).create(
                        name: nameController.text.trim(),
                        isPublic: isPublic,
                      );
                  Navigator.of(dialogContext).pop();
                  context.showSnackBar('Playlist created');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(
      BuildContext context, WidgetRef ref, String id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Delete Playlist', style: TextStyle(color: context.colors.text1)),
        content: Text(
          'Are you sure you want to delete this playlist? This action cannot be undone.',
          style: TextStyle(color: context.colors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: context.colors.text3)),
          ),
          FilledButton(
            onPressed: () {
              ref.read(playlistListProvider.notifier).delete(id);
              Navigator.of(dialogContext).pop();
              context.showSnackBar('Playlist deleted');
            },
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
