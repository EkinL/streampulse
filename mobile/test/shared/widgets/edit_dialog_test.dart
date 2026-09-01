import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/shared/widgets/edit_dialog.dart';

Future<void> _showDialog(
  WidgetTester tester, {
  required List<EditField> fields,
  required VoidCallback onSave,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => EditDialog(title: 'Edit playlist', fields: fields, onSave: onSave),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('affiche le titre et un champ pre-rempli par champ', (tester) async {
    final controller = TextEditingController(text: 'Chill mix');
    await _showDialog(
      tester,
      fields: [EditField(label: 'Name', controller: controller)],
      onSave: () {},
    );

    expect(find.text('Edit playlist'), findsOneWidget);
    expect(find.text('Chill mix'), findsOneWidget);
  });

  testWidgets('Cancel ferme le dialogue sans appeler onSave', (tester) async {
    var saved = false;
    await _showDialog(
      tester,
      fields: [EditField(label: 'Name', controller: TextEditingController())],
      onSave: () => saved = true,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(saved, isFalse);
    expect(find.byType(EditDialog), findsNothing);
  });

  testWidgets('Save appelle onSave puis ferme le dialogue', (tester) async {
    var saved = false;
    await _showDialog(
      tester,
      fields: [EditField(label: 'Name', controller: TextEditingController())],
      onSave: () => saved = true,
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, isTrue);
    expect(find.byType(EditDialog), findsNothing);
  });

  testWidgets('propage la saisie utilisateur au controller', (tester) async {
    final controller = TextEditingController();
    await _showDialog(
      tester,
      fields: [EditField(label: 'Name', controller: controller)],
      onSave: () {},
    );

    await tester.enterText(find.byType(TextField), 'New name');

    expect(controller.text, 'New name');
  });

  testWidgets('affiche plusieurs champs dans l\'ordre', (tester) async {
    await _showDialog(
      tester,
      fields: [
        EditField(label: 'Title', controller: TextEditingController()),
        EditField(label: 'Description', controller: TextEditingController(), maxLines: 3),
      ],
      onSave: () {},
    );

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
  });
}
