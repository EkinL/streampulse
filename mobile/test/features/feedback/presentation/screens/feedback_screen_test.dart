import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:streampulse/app/theme.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/features/feedback/data/feedback_repository.dart';
import 'package:streampulse/features/feedback/domain/feedback_type.dart';
import 'package:streampulse/features/feedback/presentation/screens/feedback_screen.dart';

class _MockFeedbackRepository extends Mock implements FeedbackRepository {}

/// `FeedbackScreen` pops itself on success, like it would after being pushed
/// from `/account`. A single-route router has nothing left to pop to (go_router
/// asserts the stack can't go empty), so the test router mirrors that real
/// navigation: an underlying screen, then a push onto `/feedback`.
Future<void> _pump(WidgetTester tester, {required _MockFeedbackRepository repository}) async {
  final router = GoRouter(
    initialLocation: '/account',
    routes: [
      GoRoute(path: '/account', builder: (c, s) => const Text('Mon compte')),
      GoRoute(path: '/feedback', builder: (c, s) => const FeedbackScreen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [feedbackRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
    ),
  );
  router.push('/feedback');
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    // PackageInfo.fromPlatform() touches a platform channel that isn't
    // mocked in widget tests by default; without this every screen pump
    // would hit the un-mocked-channel error path in loadAppVersion.
    PackageInfo.setMockInitialValues(
      appName: 'StreamPulse',
      packageName: 'fr.streampulse.app',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: '',
    );
    registerFallbackValue(FeedbackType.bug);
  });

  late _MockFeedbackRepository repository;

  setUp(() {
    repository = _MockFeedbackRepository();
  });

  testWidgets('le bouton envoyer est desactive tant que le message est vide', (tester) async {
    await _pump(tester, repository: repository);

    await tester.tap(find.text('Envoyer'));
    await tester.pump();

    expect(find.text('Un message est requis.'), findsOneWidget);
    verifyNever(() => repository.submitFeedback(
          type: any(named: 'type'),
          message: any(named: 'message'),
          appVersion: any(named: 'appVersion'),
        ));
  });

  testWidgets('envoie le signalement et revient en arriere', (tester) async {
    when(() => repository.submitFeedback(
          type: any(named: 'type'),
          message: any(named: 'message'),
          appVersion: any(named: 'appVersion'),
        )).thenAnswer((_) async {});

    await _pump(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'Le lecteur coupe le son.');
    await tester.tap(find.text('Envoyer'));
    await tester.pump();

    verify(() => repository.submitFeedback(
          type: any(named: 'type'),
          message: 'Le lecteur coupe le son.',
          appVersion: any(named: 'appVersion'),
        )).called(1);

    // Un seul pump : assez pour que le microtask du repository se resolve et
    // que le snackbar/pop s'executent, pas assez pour laisser le minuteur
    // d'auto-fermeture du snackbar (via pumpAndSettle) l'escamoter avant
    // l'assertion.
    await tester.pump();
    expect(find.text('Merci, votre signalement a bien été envoyé.'), findsOneWidget);

    // Laisse la transition de retour et le minuteur du snackbar se terminer,
    // pour ne pas finir le test avec une animation encore en cours.
    await tester.pumpAndSettle();
  });

  testWidgets('affiche le message d\'erreur du serveur en cas d\'echec', (tester) async {
    when(() => repository.submitFeedback(
          type: any(named: 'type'),
          message: any(named: 'message'),
          appVersion: any(named: 'appVersion'),
        )).thenThrow(const ApiException(message: 'panne du serveur'));

    await _pump(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'Un message quelconque');
    await tester.tap(find.text('Envoyer'));
    await tester.pump();

    expect(find.text('panne du serveur'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
