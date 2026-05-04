import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../providers/live_stream_provider.dart';
import 'audio_waveform.dart';

class AudioPlayerBar extends ConsumerWidget {
  final String title;
  final String streamId;
  final bool isLive;

  const AudioPlayerBar({
    super.key,
    required this.title,
    required this.streamId,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveState = ref.watch(liveStreamProvider);
    // Only react to this bar's stream
    final isThisStream = liveState.streamId == streamId;
    final isConnected = isThisStream && liveState.isConnected;
    final isConnecting = isThisStream && liveState.isConnecting;
    final isReceivingData = isThisStream && liveState.isReceivingData;
    final statusText = isThisStream ? liveState.statusText : 'Tap play to listen';

    // Notify provider when stream status changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isLive && isConnected) {
        ref.read(liveStreamProvider.notifier).onStreamEnded();
      }
      if (isLive && !isConnected && !isConnecting && liveState.streamId != streamId) {
        ref.read(liveStreamProvider.notifier).onStreamLive(streamId);
      }
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SP.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isConnected)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AudioWaveform(
                isActive: isReceivingData,
                color: SP.accent,
                barCount: 30,
                height: 50,
              ),
            ),
          Row(
            children: [
              _buildPlayButton(
                context: context,
                ref: ref,
                isConnected: isConnected,
                isConnecting: isConnecting,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: SP.text1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isReceivingData
                            ? Colors.green
                            : isConnected
                                ? Colors.orange
                                : SP.text3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isConnected)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: isReceivingData ? Colors.green : Colors.orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isReceivingData ? Colors.green : Colors.orange)
                            .withOpacity(0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton({
    required BuildContext context,
    required WidgetRef ref,
    required bool isConnected,
    required bool isConnecting,
  }) {
    if (isConnecting) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2, color: SP.accent),
        ),
      );
    }

    return IconButton(
      icon: Icon(
        isConnected ? Icons.stop_circle : Icons.play_circle_filled,
        size: 48,
        color: isConnected
            ? SP.error
            : isLive
                ? SP.accent
                : SP.text3.withOpacity(0.3),
      ),
      onPressed: isLive || isConnected
          ? () {
              if (isConnected) {
                ref.read(liveStreamProvider.notifier).disconnect();
              } else {
                ref.read(liveStreamProvider.notifier).connect(streamId);
              }
            }
          : null,
      padding: EdgeInsets.zero,
    );
  }
}
