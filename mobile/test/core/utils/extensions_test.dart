import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/utils/extensions.dart';

void main() {
  group('StringExtensions.capitalize', () {
    test('met en majuscule la premiere lettre', () {
      expect('hello'.capitalize, 'Hello');
    });

    test('laisse une chaine vide telle quelle', () {
      expect(''.capitalize, '');
    });
  });

  group('StringExtensions.isValidEmail', () {
    test('vrai pour un email bien forme', () {
      expect('alice@example.com'.isValidEmail, isTrue);
    });

    test('faux pour une chaine sans arobase', () {
      expect('not-an-email'.isValidEmail, isFalse);
    });
  });

  group('StringExtensions.initials', () {
    test('prend la premiere lettre de deux mots', () {
      expect('Alice Martin'.initials, 'AM');
    });

    test('ignore les espaces multiples entre les mots', () {
      expect('Alice   Martin'.initials, 'AM');
    });

    test('prend les deux premieres lettres d\'un seul mot long', () {
      expect('Alice'.initials, 'AL');
    });

    test('prend le mot entier si un seul caractere', () {
      expect('A'.initials, 'A');
    });
  });

  group('BuildContextExtensions', () {
    testWidgets('theme/textTheme/colorScheme/mediaQuery/screenSize exposent le contexte ambiant',
        (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(capturedContext.theme, Theme.of(capturedContext));
      expect(capturedContext.textTheme, Theme.of(capturedContext).textTheme);
      expect(capturedContext.colorScheme, Theme.of(capturedContext).colorScheme);
      expect(capturedContext.mediaQuery, MediaQuery.of(capturedContext));
      expect(capturedContext.screenSize, MediaQuery.of(capturedContext).size);
    });

    testWidgets('showSnackBar affiche le message avec la couleur primaire par defaut',
        (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      capturedContext.showSnackBar('Saved');
      await tester.pump();

      expect(find.text('Saved'), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, Theme.of(capturedContext).colorScheme.primary);
    });

    testWidgets('showSnackBar avec isError utilise la couleur d\'erreur', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      capturedContext.showSnackBar('Failed', isError: true);
      await tester.pump();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, Theme.of(capturedContext).colorScheme.error);
    });

    testWidgets('showSnackBar masque le snackbar precedent avant d\'en montrer un nouveau',
        (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      capturedContext.showSnackBar('First');
      await tester.pump();
      capturedContext.showSnackBar('Second');
      await tester.pump();

      expect(find.text('Second'), findsOneWidget);
    });
  });
}
