import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:streampulse/features/auth/presentation/screens/privacy_policy_screen.dart';
import 'package:streampulse/app/theme.dart';

void main() {
  testWidgets('affiche le titre et les sections de la politique de confidentialite', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const PrivacyPolicyScreen()),
    );

    expect(find.text('Politique de confidentialité'), findsOneWidget);
    expect(find.text('Ce que nous conservons'), findsOneWidget);
    expect(find.text('Pourquoi'), findsOneWidget);
    expect(find.text('Combien de temps'), findsOneWidget);
    expect(find.text('Vos droits'), findsOneWidget);
  });

  testWidgets('le bouton retour depile l\'ecran', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const Text('Home')),
        GoRoute(path: '/privacy', builder: (c, s) => const PrivacyPolicyScreen()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router));
    router.push('/privacy');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });
}
