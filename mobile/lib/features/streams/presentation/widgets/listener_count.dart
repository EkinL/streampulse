import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

class ListenerCount extends StatelessWidget {
  final int count;

  const ListenerCount({
    super.key,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.headphones,
          size: 14,
          color: SP.accent,
        ),
        const SizedBox(width: 4),
        Text(
          _formatCount(count),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SP.accent,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
