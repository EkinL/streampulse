import 'package:flutter/material.dart';
import '../../../../app/theme.dart';
import '../../domain/playlist_model.dart';

class PlaylistTile extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const PlaylistTile({
    super.key,
    required this.playlist,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: SP.surface,
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
              color: SP.tag,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.queue_music, color: SP.accent),
          ),
        ),
        title: Text(
          playlist.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SP.text1),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${playlist.trackCount} titre${playlist.trackCount != 1 ? 's' : ''}'
          '${playlist.isPublic ? ' \u2022 Public' : ''}',
          style: const TextStyle(fontSize: 12, color: SP.text3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: onDelete != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline, color: SP.error),
                tooltip: 'Supprimer',
                onPressed: onDelete,
              )
            : const Icon(Icons.chevron_right, color: SP.text3),
        onTap: onTap,
      ),
    );
  }
}
