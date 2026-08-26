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
      backgroundColor: SP.bg,
      appBar: AppBar(
        backgroundColor: SP.surface,
        foregroundColor: SP.text1,
        title: const Text('Playlists'),
      ),
      body: RefreshIndicator(
        color: SP.accent,
        onRefresh: () async {
          await ref.read(playlistListProvider.notifier).fetch();
        },
        child: playlistsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: SP.accent)),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: $error', style: const TextStyle(color: SP.text2)),
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
                    const Icon(
                      Icons.queue_music,
                      size: 80,
                      color: SP.text3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No playlists yet',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: SP.text3,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create your first playlist',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: SP.text3,
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
          backgroundColor: SP.accent,
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
          backgroundColor: SP.surface,
          title: const Text('Create Playlist', style: TextStyle(color: SP.text1)),
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
                title: const Text('Public', style: TextStyle(color: SP.text1)),
                value: isPublic,
                activeThumbColor: SP.accent,
                onChanged: (v) => setDialogState(() => isPublic = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: SP.text3)),
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
        backgroundColor: SP.surface,
        title: const Text('Delete Playlist', style: TextStyle(color: SP.text1)),
        content: const Text(
          'Are you sure you want to delete this playlist? This action cannot be undone.',
          style: TextStyle(color: SP.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: SP.text3)),
          ),
          FilledButton(
            onPressed: () {
              ref.read(playlistListProvider.notifier).delete(id);
              Navigator.of(dialogContext).pop();
              context.showSnackBar('Playlist deleted');
            },
            style: FilledButton.styleFrom(
              backgroundColor: SP.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
