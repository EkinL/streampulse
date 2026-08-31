import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../features/streams/presentation/providers/live_stream_provider.dart';
import '../../features/streams/presentation/providers/stream_provider.dart';

/// Barre persistante du flux en direct — distincte du [MiniPlayer] de
/// musique, qui suit un système de lecture séparé (pistes téléversées).
/// Visible sur Direct/Playlists/Favoris dès qu'un flux est connecté.
class LiveMiniPlayer extends ConsumerWidget {
  const LiveMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveState = ref.watch(liveStreamProvider);
    if (!liveState.isConnected || liveState.streamId == null) {
      return const SizedBox.shrink();
    }

    final streamId = liveState.streamId!;
    // Le nombre d'auditeurs n'est pas dupliqué dans liveStreamProvider : on
    // le lit depuis la liste déjà maintenue par streamListProvider, pour
    // éviter un second flux de données et un affichage qui diverge.
    final listenerCount = ref.watch(streamListProvider).maybeWhen(
          data: (streams) {
            for (final s in streams) {
              if (s.id == streamId) return s.listenerCount;
            }
            return null;
          },
          orElse: () => null,
        );

    return GestureDetector(
      onTap: () => context.push('/streams/$streamId'),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.colors.divider, width: 0.5)),
        ),
        child: Column(
          children: [
            // Indicateur de tampon — pas une position de lecture, un flux
            // continu n'en a pas (cf. handoff design).
            SizedBox(
              height: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: liveState.isReceivingData ? 0.38 : 0,
                  child: Container(color: context.colors.accent),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [SP.gradEnd, context.colors.accent],
                        ),
                      ),
                      child: const Icon(Icons.podcasts, color: SP.btnText, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            liveState.title ?? 'Direct',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.text1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            listenerCount != null
                                ? 'En direct • ${_formatCount(listenerCount)} à l\'écoute'
                                : 'En direct',
                            style: TextStyle(fontSize: 12, color: context.colors.text2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Suspend sans quitter l'écran courant (n'appelle pas
                    // Navigator, contrairement au tap sur le corps).
                    IconButton(
                      tooltip: 'Pause',
                      onPressed: () => ref.read(liveStreamProvider.notifier).disconnect(),
                      icon: Icon(Icons.pause_circle_filled, color: context.colors.accent, size: 36),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)} K';
    return '$count';
  }
}
