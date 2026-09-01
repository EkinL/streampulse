import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/shared/widgets/loading_indicator.dart';

void main() {
  testWidgets('affiche un indicateur de progression sans message', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoadingIndicator()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('affiche le message quand il est fourni', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoadingIndicator(message: 'Loading tracks...')));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading tracks...'), findsOneWidget);
  });
}
