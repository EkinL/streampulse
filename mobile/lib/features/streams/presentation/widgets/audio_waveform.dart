import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AudioWaveform extends StatefulWidget {
  final bool isActive;
  final Color color;
  /// Dégradé optionnel appliqué à chaque barre (prioritaire sur [color]),
  /// pour le rendu du VU-mètre de la console diffuseur.
  final Gradient? gradient;
  final int barCount;
  final double height;

  const AudioWaveform({
    super.key,
    required this.isActive,
    this.color = Colors.green,
    this.gradient,
    this.barCount = 20,
    this.height = 40,
  });

  @override
  State<AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<double> _barHeights;
  final _random = Random();

  /// La maquette coupe toute animation sous `prefers-reduced-motion`; côté
  /// Flutter l'équivalent est ce drapeau système, lisible sans BuildContext.
  bool get _reducedMotion =>
      SchedulerBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  @override
  void initState() {
    super.initState();
    _barHeights = List.generate(widget.barCount, (_) => 0.2);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(_updateBars);

    if (widget.isActive && !_reducedMotion) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AudioWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_reducedMotion && !_controller.isAnimating) {
      _controller.repeat();
    } else if ((!widget.isActive || _reducedMotion) && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        _barHeights = List.generate(widget.barCount, (_) => 0.15);
      });
    }
  }

  void _updateBars() {
    if (!mounted || !widget.isActive) return;
    setState(() {
      for (int i = 0; i < _barHeights.length; i++) {
        _barHeights[i] = 0.15 + _random.nextDouble() * 0.85;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = _reducedMotion;

    return SizedBox(
      height: widget.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(widget.barCount, (index) {
          final heightFraction = reducedMotion ? 0.55 : _barHeights[index];
          final decoration = widget.gradient != null
              ? BoxDecoration(gradient: widget.gradient, borderRadius: BorderRadius.circular(2))
              : BoxDecoration(
                  color: !widget.isActive || reducedMotion
                      ? widget.color.withValues(alpha: reducedMotion && widget.isActive ? 1 : 0.2)
                      : widget.color.withValues(alpha: 0.7 + 0.3 * heightFraction),
                  borderRadius: BorderRadius.circular(2),
                );

          return AnimatedContainer(
            duration: reducedMotion ? Duration.zero : const Duration(milliseconds: 120),
            width: 3,
            height: widget.height * heightFraction,
            decoration: decoration,
          );
        }),
      ),
    );
  }
}
