import 'package:flutter/material.dart';
import '../../../../app/theme.dart';
import '../../domain/stream_model.dart';
import 'audio_waveform.dart';

class StreamCard extends StatelessWidget {
  final StreamModel stream;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;
  final VoidCallback? onEdit;
  /// Cœur plein plutôt que contour — utilisé par l'écran Favoris.
  final bool favoriteFilled;

  const StreamCard({
    super.key,
    required this.stream,
    this.onTap,
    this.onFavorite,
    this.onEdit,
    this.favoriteFilled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SP.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album art placeholder
            Container(
              width: 96,
              height: 96,
              padding: stream.isLive ? const EdgeInsets.symmetric(horizontal: 14, vertical: 18) : null,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: stream.isLive
                      ? [SP.gradEnd.withValues(alpha: 0.6), SP.gradStart.withValues(alpha: 0.3)]
                      : [SP.surfaceVariant, SP.tag],
                ),
              ),
              child: stream.isLive
                  ? const AudioWaveform(isActive: true, color: SP.accent, barCount: 5, height: 60)
                  : const Center(
                      child: Icon(Icons.mic_off, size: 30, color: SP.textMuted),
                    ),
            ),
            const SizedBox(width: 16),
            // Content
            Expanded(
              child: SizedBox(
                height: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: badge + listeners + edit
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _StatusBadge(isLive: stream.isLive),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (stream.isLive)
                              Row(
                                children: [
                                  const Icon(Icons.headphones, size: 11, color: SP.text2),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatCount(stream.listenerCount),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SP.text2),
                                  ),
                                ],
                              ),
                            if (onEdit != null) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: onEdit,
                                child: const Icon(Icons.edit, color: SP.text3, size: 16),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Title
                    Text(
                      stream.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: SP.text1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (stream.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        stream.description,
                        style: const TextStyle(fontSize: 12, color: SP.text2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const Spacer(),
                    // Tags row
                    Row(
                      children: [
                        _FormatTag(stream.format.toUpperCase()),
                        if (onFavorite != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: onFavorite,
                            behavior: HitTestBehavior.opaque,
                            // Cible tactile 44x44 sans agrandir la place réservée
                            // dans la mise en page (18x18) : OverflowBox déborde
                            // visuellement sans changer la taille rapportée au
                            // parent (Container refuse les marges négatives).
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: OverflowBox(
                                minWidth: 44,
                                minHeight: 44,
                                maxWidth: 44,
                                maxHeight: 44,
                                child: Icon(
                                  favoriteFilled ? Icons.favorite : Icons.favorite_border,
                                  size: 18,
                                  color: favoriteFilled ? SP.accent : SP.text3,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
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
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isLive;
  const _StatusBadge({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLive ? SP.liveBg : SP.offlineBg,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(color: SP.liveText, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            isLive ? 'LIVE' : 'HORS LIGNE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: isLive ? SP.liveText : SP.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatTag extends StatelessWidget {
  final String text;
  const _FormatTag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: SP.tag,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.45,
          color: SP.textMuted,
        ),
      ),
    );
  }
}
