import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/shared/providers/volume_provider.dart';
import 'package:streampulse/shared/widgets/volume_control.dart';

class _FakeVolumeStore implements VolumeStore {
  double? saved;

  @override
  Future<double?> load() async => null;

  @override
  Future<void> save(double volume) async => saved = volume;
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        volumeProvider.overrideWith((ref) => VolumeNotifier(_FakeVolumeStore())),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
}

void main() {
  testWidgets('affiche le pourcentage du volume par defaut', (tester) async {
    await _pump(tester, const VolumeControl());
    await tester.pump();

    expect(find.text('80%'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('masque le pourcentage en mode compact', (tester) async {
    await _pump(tester, const VolumeControl(compact: true));
    await tester.pump();

    expect(find.text('80%'), findsNothing);
  });

  testWidgets('le bouton mute coupe puis restaure le volume', (tester) async {
    await _pump(tester, const VolumeControl());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump();

    expect(find.text('0%'), findsOneWidget);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_off));
    await tester.pump();

    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('deplacer le slider met a jour le pourcentage affiche', (tester) async {
    await _pump(tester, const VolumeControl());
    await tester.pump();

    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pump();

    expect(find.text('80%'), findsNothing);
  });
}
