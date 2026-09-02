import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../shared/widgets/volume_control.dart';
import '../../../auth/domain/auth_state.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
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
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
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
                color: context.colors.accent,
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.text1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isReceivingData ? context.colors.success : context.colors.text3,
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
                    color: isReceivingData ? context.colors.success : context.colors.text3,
                    shape: BoxShape.circle,
                    boxShadow: isReceivingData
                        ? [BoxShadow(color: context.colors.success.withValues(alpha: 0.5), blurRadius: 6)]
                        : null,
                  ),
                ),
            ],
          ),
          if (isConnected)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: VolumeControl(compact: true),
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
      return SizedBox(
        width: 48,
        height: 48,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.accent),
        ),
      );
    }

    final onPressed = isLive || isConnected
        ? () {
            if (isConnected) {
              ref.read(liveStreamProvider.notifier).disconnect();
              return;
            }
            // L'écoute est réservée aux comptes connectés (le backend
            // répondrait 401 sur /streams/:id/audio de toute façon).
            if (ref.read(authProvider) is! AuthAuthenticated) {
              context.promptLogin('Connectez-vous pour écouter le direct');
              return;
            }
            ref.read(liveStreamProvider.notifier).connect(streamId, title: title);
          }
        : null;

    if (isConnected) {
      // Cercle plein + carré arrondi sombre à l'intérieur, comme la maquette
      // (Icons.stop_circle ne peut pas rendre ces deux teintes distinctes).
      return GestureDetector(
        onTap: onPressed,
        child: Semantics(
          button: true,
          label: 'Stop listening',
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: context.colors.error, shape: BoxShape.circle),
            child: Center(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: context.colors.bg, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Listen',
      icon: Icon(
        Icons.play_circle_filled,
        size: 48,
        color: isLive ? context.colors.accent : context.colors.text3.withValues(alpha: 0.3),
      ),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
    );
  }
}
