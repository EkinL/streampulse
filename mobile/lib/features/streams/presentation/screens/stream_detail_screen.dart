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

    return Scaffold(
      backgroundColor: SP.bg,
      appBar: AppBar(
        backgroundColor: SP.surface,
        foregroundColor: SP.text1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Stream Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: () {
              ref
                  .read(streamListProvider.notifier)
                  .toggleFavorite(widget.streamId)
                  .then((_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to favorites')),
                  );
                }
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
                              SP.accent.withOpacity(0.2),
                              SP.accent.withOpacity(0.05),
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
                                const Icon(
                                  Icons.radio,
                                  size: 48,
                                  color: SP.accent,
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
                                              color: SP.text1,
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
                                color: SP.text1,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          stream.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: SP.text2),
                        ),
                        const SizedBox(height: 24),
                      ],
                      Text(
                        'Details',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: SP.text1,
                                ),
                      ),
                      const SizedBox(height: 12),
                      _DetailRow(
                        icon: Icons.headphones,
                        label: 'Listeners',
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
                            color: SP.tag,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            stream.format.toUpperCase(),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: SP.text2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _DetailRow(
                        icon: Icons.calendar_today,
                        label: 'Created',
                        child: Text(
                          DateFormat.yMMMd().add_jm().format(stream.createdAt),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: SP.text2),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isLive ? SP.liveBg.withOpacity(0.15) : SP.offlineBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: const BoxDecoration(
                color: SP.liveBg,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            isLive ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: isLive ? SP.liveText : SP.text3,
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
          color: SP.text3,
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: SP.text3,
              ),
        ),
        child,
      ],
    );
  }
}
