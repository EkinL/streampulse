import 'package:flutter/material.dart';
import '../../../../app/theme.dart';
import '../../domain/playlist_model.dart';

class PlaylistTile extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback? onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const PlaylistTile({
    super.key,
    required this.playlist,
    this.onTap,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // Playlist cover placeholder — decorative, title/subtitle carry the info
        leading: ExcludeSemantics(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.colors.tag,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.queue_music, color: context.colors.accent),
          ),
        ),
        title: Text(
          playlist.name,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.colors.text1),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${playlist.trackCount} titre${playlist.trackCount != 1 ? 's' : ''}'
          '${playlist.isPublic ? ' \u2022 Public' : ''}'
          '${playlist.ownerUsername != null ? ' \u2022 ${playlist.ownerUsername}' : ''}',
          style: TextStyle(fontSize: 12, color: context.colors.text3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Menu proprietaire (renommer/supprimer) quand au moins une action est
        // fournie ; sinon simple chevron pour les playlists des autres.
        trailing: (onRename != null || onDelete != null)
            ? PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: context.colors.text3),
                tooltip: 'Options',
                color: context.colors.surface,
                onSelected: (value) {
                  if (value == 'rename') onRename?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => [
                  if (onRename != null)
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 20, color: context.colors.text2),
                          const SizedBox(width: 12),
                          Text('Renommer',
                              style: TextStyle(color: context.colors.text1)),
                        ],
                      ),
                    ),
                  if (onDelete != null)
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 20, color: context.colors.error),
                          const SizedBox(width: 12),
                          Text('Supprimer',
                              style: TextStyle(color: context.colors.error)),
                        ],
                      ),
                    ),
                ],
              )
            : Icon(Icons.chevron_right, color: context.colors.text3),
        onTap: onTap,
      ),
    );
  }
}
