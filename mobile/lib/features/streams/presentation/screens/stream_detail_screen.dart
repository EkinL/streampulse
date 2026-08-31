import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme.dart';
import '../providers/stream_provider.dart';
import '../widgets/audio_player_bar.dart';
import '../widgets/listener_count.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/error_widget.dart' as app_error;
import '../../../favorites/presentation/providers/favorites_provider.dart';

class StreamDetailScreen extends ConsumerStatefulWidget {
  final String streamId;

  const StreamDetailScreen({
    super.key,
    required this.streamId,
  });

  @override
  ConsumerState<StreamDetailScreen> createState() => _StreamDetailScreenState();
}

class _StreamDetailScreenState extends ConsumerState<StreamDetailScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Auto-refresh stream details every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        ref.invalidate(streamDetailProvider(widget.streamId));
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final streamAsync = ref.watch(streamDetailProvider(widget.streamId));
    final isFavorite = ref.watch(favoriteIdsProvider).contains(widget.streamId);

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.text1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Détail du flux'),
        actions: [
          IconButton(
            icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? context.colors.accent : null),
            tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
            onPressed: () {
              final notifier = ref.read(favoritesProvider.notifier);
              final action = isFavorite
                  ? notifier.remove(widget.streamId)
                  : notifier.add(widget.streamId);
              action.then((_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isFavorite
                        ? 'Removed from favorites'
                        : 'Added to favorites'),
                  ),
                );
              });
            },
          ),
        ],
      ),
      body: streamAsync.when(
        loading: () => const LoadingIndicator(),
        error: (error, _) => app_error.AppErrorWidget(
          message: error.toString(),
          onRetry: () => ref.invalidate(streamDetailProvider(widget.streamId)),
        ),
        data: (stream) {
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              context.colors.accent.withValues(alpha: 0.2),
                              context.colors.accent.withValues(alpha: 0.05),
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
                              children: [
                                Icon(
                                  Icons.radio,
                                  size: 48,
                                  color: context.colors.accent,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stream.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: context.colors.text1,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      _StatusBadge(isLive: stream.isLive),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (stream.description.isNotEmpty) ...[
                        Text(
                          'Description',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: context.colors.text1,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          stream.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: context.colors.text2),
                        ),
                        const SizedBox(height: 24),
                      ],
                      Text(
                        'Détails',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: context.colors.text1,
                                ),
                      ),
                      const SizedBox(height: 12),
                      _DetailRow(
                        icon: Icons.headphones,
                        label: 'Auditeurs',
                        child: ListenerCount(count: stream.listenerCount),
                      ),
                      const SizedBox(height: 8),
                      _DetailRow(
                        icon: Icons.audiotrack,
                        label: 'Format',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.colors.tag,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            stream.format.toUpperCase(),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: context.colors.text2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _DetailRow(
                        icon: Icons.calendar_today,
                        label: 'Créé le',
                        child: Text(
                          DateFormat.yMMMd().add_jm().format(stream.createdAt),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: context.colors.text2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: AudioPlayerBar(
                  title: stream.title,
                  streamId: stream.id,
                  isLive: stream.isLive,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isLive;
  const _StatusBadge({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isLive ? SP.liveBg.withValues(alpha: 0.15) : context.colors.offlineBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: const BoxDecoration(
                color: SP.liveBg,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            isLive ? 'LIVE' : 'HORS LIGNE',
            style: TextStyle(
              // Sur ce badge translucide, le texte reprend la teinte claire
              // (liveBg), pas le liveText foncé prévu pour un fond plein.
              color: isLive ? SP.liveBg : context.colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: context.colors.text3,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.colors.text3,
              ),
        ),
        child,
      ],
    );
  }
}
