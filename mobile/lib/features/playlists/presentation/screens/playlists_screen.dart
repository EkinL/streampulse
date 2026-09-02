import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/domain/auth_state.dart';
import '../providers/playlist_provider.dart';
import '../../domain/playlist_model.dart';
import '../widgets/playlist_tile.dart';
import '../../../../core/utils/extensions.dart';

class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : '';

    return Scaffold(
      backgroundColor: context.colors.altBg,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.text1,
        title: const Text('Playlists'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: context.colors.accent,
          unselectedLabelColor: context.colors.text3,
          indicatorColor: context.colors.accent,
          tabs: const [
            Tab(text: 'Mes playlists'),
            Tab(text: 'Découvrir'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MyPlaylistsTab(currentUserId: currentUserId),
          _PublicPlaylistsTab(currentUserId: currentUserId),
        ],
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
}

class _MyPlaylistsTab extends ConsumerWidget {
  final String currentUserId;

  const _MyPlaylistsTab({required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistListProvider);

    return RefreshIndicator(
      color: context.colors.accent,
      onRefresh: () async {
        await ref.read(playlistListProvider.notifier).fetch();
      },
      child: playlistsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: context.colors.accent)),
        error: (error, _) => _ErrorView(
          message: 'Error: $error',
          onRetry: () => ref.read(playlistListProvider.notifier).fetch(),
        ),
        data: (playlists) {
          if (playlists.isEmpty) {
            return const _EmptyView(
              title: 'No playlists yet',
              subtitle: 'Create your first playlist',
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
                onRename: () {
                  _showRenameDialog(context, ref, playlist);
                },
                onDelete: () {
                  _showDeleteConfirmation(context, ref, playlist.id);
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showRenameDialog(
      BuildContext context, WidgetRef ref, PlaylistModel playlist) {
    final nameController = TextEditingController(text: playlist.name);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text('Renommer la playlist',
            style: TextStyle(color: context.colors.text1)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom',
            hintText: 'Nom de la playlist',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Annuler',
                style: TextStyle(color: context.colors.text3)),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty || name == playlist.name) {
                Navigator.of(dialogContext).pop();
                return;
              }
              Navigator.of(dialogContext).pop();
              try {
                await ref
                    .read(playlistListProvider.notifier)
                    .update(id: playlist.id, name: name);
                if (context.mounted) {
                  context.showSnackBar('Playlist renommée');
                }
              } catch (e) {
                if (context.mounted) {
                  context.showSnackBar('Échec du renommage : $e',
                      isError: true);
                }
              }
            },
            child: const Text('Renommer'),
          ),
        ],
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

class _PublicPlaylistsTab extends ConsumerWidget {
  final String currentUserId;

  const _PublicPlaylistsTab({required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(publicPlaylistListProvider);

    return RefreshIndicator(
      color: context.colors.accent,
      onRefresh: () async {
        await ref.read(publicPlaylistListProvider.notifier).fetch();
      },
      child: playlistsAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: context.colors.accent)),
        error: (error, _) => _ErrorView(
          message: 'Error: $error',
          onRetry: () => ref.read(publicPlaylistListProvider.notifier).fetch(),
        ),
        data: (playlists) {
          // Playlists the current user owns already show up under "Mes
          // playlists" — no need to list them twice here.
          final others =
              playlists.where((p) => p.ownerId != currentUserId).toList();
          if (others.isEmpty) {
            return const _EmptyView(
              title: 'No public playlists yet',
              subtitle: 'Playlists made public by other users will show up here',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: others.length,
            itemBuilder: (context, index) {
              final playlist = others[index];
              return PlaylistTile(
                playlist: playlist,
                onTap: () => context.push('/playlists/${playlist.id}'),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyView({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
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
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: context.colors.text3,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.text3,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, style: TextStyle(color: context.colors.text2)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
