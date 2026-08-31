import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../providers/volume_provider.dart';

/// Slider de volume + bouton mute, branche sur [volumeProvider].
class VolumeControl extends ConsumerWidget {
  final bool compact;

  const VolumeControl({super.key, this.compact = false});

  IconData _iconFor(double volume) {
    if (volume == 0) return Icons.volume_off;
    if (volume < 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(volumeProvider);
    final notifier = ref.read(volumeProvider.notifier);
    final percent = (volume * 100).round();
    final iconSize = compact ? 18.0 : 22.0;

    return Row(
      children: [
        IconButton(
          tooltip: volume == 0 ? 'Unmute' : 'Mute',
          iconSize: iconSize,
          padding: compact ? EdgeInsets.zero : null,
          constraints: compact
              // 48x48 minimum tap target (Material recommendation), even though
              // the visible icon stays small (iconSize 18) to fit the compact bar.
              ? const BoxConstraints(minWidth: 48, minHeight: 48)
              : null,
          onPressed: notifier.toggleMute,
          icon: Icon(_iconFor(volume), color: context.colors.text2),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: context.colors.text2,
              inactiveTrackColor: context.colors.surfaceVariant,
              thumbColor: context.colors.text1,
              overlayColor: context.colors.text1.withValues(alpha: 0.1),
              trackHeight: compact ? 2 : 3,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: compact ? 4 : 5,
              ),
            ),
            child: Semantics(
              slider: true,
              label: 'Volume',
              value: '$percent%',
              child: Slider(
                value: volume,
                onChanged: notifier.set,
              ),
            ),
          ),
        ),
        if (!compact)
          SizedBox(
            width: 40,
            child: Text(
              '$percent%',
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 12, color: context.colors.text3),
            ),
          ),
      ],
    );
  }
}
