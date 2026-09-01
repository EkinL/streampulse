import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/shared/widgets/error_widget.dart';

void main() {
  testWidgets('affiche le message sans bouton de retry par defaut', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppErrorWidget(message: 'Network unreachable')),
    );

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Network unreachable'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('affiche un bouton Try Again et le declenche quand onRetry est fourni',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppErrorWidget(message: 'boom', onRetry: () => retried = true),
      ),
    );

    expect(find.text('Try Again'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    expect(retried, isTrue);
  });
}
