import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/streams/presentation/widgets/listener_count.dart';
import 'package:streampulse/app/theme.dart';

Future<void> _pump(WidgetTester tester, int count) =>
    tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: ListenerCount(count: count))));

void main() {
  testWidgets('affiche le nombre brut sous 1000', (tester) async {
    await _pump(tester, 42);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('formate en K entre 1 000 et 999 999', (tester) async {
    await _pump(tester, 1500);
    expect(find.text('1.5K'), findsOneWidget);
  });

  testWidgets('formate en M a partir d\'un million', (tester) async {
    await _pump(tester, 2500000);
    expect(find.text('2.5M'), findsOneWidget);
  });

  testWidgets('affiche l\'icone casque', (tester) async {
    await _pump(tester, 10);
    expect(find.byIcon(Icons.headphones), findsOneWidget);
  });
}
