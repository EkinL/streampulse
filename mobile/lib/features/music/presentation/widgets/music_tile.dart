import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../domain/music_model.dart';
import '../providers/music_favorites_provider.dart';

class MusicTile extends ConsumerWidget {
  final MusicModel music;
  final VoidCallback? onTap;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onEdit;

  const MusicTile({
    super.key,
    required this.music,
    this.onTap,
    this.onAddToPlaylist,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(musicFavoritesProvider);
    final isFav = favorites.contains(music.id);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SP.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Album art placeholder — decorative, title/artist below carry the info
            ExcludeSemantics(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [SP.gradEnd, SP.accent],
                  ),
                ),
                child: const Icon(Icons.music_note, color: SP.btnText, size: 28),
              ),
            ),
            const SizedBox(width: 12),
            // Title + Artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    music.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: SP.text1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    music.artist.isNotEmpty ? music.artist : 'Unknown artist',
                    style: const TextStyle(
                      fontSize: 12,
                      color: SP.text2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Duration
            Text(
              music.formattedDuration,
              style: const TextStyle(
                fontSize: 12,
                color: SP.text3,
              ),
            ),
            const SizedBox(width: 4),
            // Edit icon (if callback provided)
            if (onEdit != null)
              GestureDetector(
                onTap: onEdit,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.edit, color: SP.text3, size: 16),
                ),
              ),
            // Favorite heart button
            GestureDetector(
              onTap: () {
                ref.read(musicFavoritesProvider.notifier).toggle(music.id);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? SP.liveBg : SP.text3,
                  size: 22,
                ),
              ),
            ),
            // Play button
            GestureDetector(
              onTap: onTap,
              child: const Icon(
                Icons.play_circle_filled,
                color: SP.accent,
                size: 32,
              ),
            ),
            // Popup menu
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: SP.text3, size: 20),
              color: SP.surfaceVariant,
              onSelected: (value) {
                if (value == 'add_to_playlist' && onAddToPlaylist != null) {
                  onAddToPlaylist!();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'add_to_playlist',
                  child: Text(
                    'Add to playlist',
                    style: TextStyle(color: SP.text1, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
