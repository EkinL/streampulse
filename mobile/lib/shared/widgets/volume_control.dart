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
              ? const BoxConstraints(minWidth: 32, minHeight: 32)
              : null,
          onPressed: notifier.toggleMute,
          icon: Icon(_iconFor(volume), color: SP.text2),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: SP.text2,
              inactiveTrackColor: SP.surfaceVariant,
              thumbColor: SP.text1,
              overlayColor: SP.text1.withValues(alpha: 0.1),
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
              style: const TextStyle(fontSize: 12, color: SP.text3),
            ),
          ),
      ],
    );
  }
}
