import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/streams/presentation/widgets/audio_waveform.dart';
import 'package:streampulse/app/theme.dart';

void main() {
  testWidgets('affiche barCount barres', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme, home: const Scaffold(body: AudioWaveform(isActive: false, barCount: 12)),
      ),
    );

    expect(find.byType(AnimatedContainer), findsNWidgets(12));
  });

  testWidgets('anime les barres quand isActive est vrai', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme, home: const Scaffold(body: AudioWaveform(isActive: true, barCount: 6)),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AnimatedContainer), findsNWidgets(6));
  });

  testWidgets('bascule de actif a inactif sans planter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme, home: const Scaffold(body: AudioWaveform(isActive: true, barCount: 6)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme, home: const Scaffold(body: AudioWaveform(isActive: false, barCount: 6)),
      ),
    );
    await tester.pump();

    expect(find.byType(AnimatedContainer), findsNWidgets(6));
  });

  testWidgets('libere l\'AnimationController a la destruction du widget', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme, home: const Scaffold(body: AudioWaveform(isActive: true, barCount: 4)),
      ),
    );

    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: const Scaffold(body: SizedBox.shrink())));

    expect(tester.takeException(), isNull);
  });
}
