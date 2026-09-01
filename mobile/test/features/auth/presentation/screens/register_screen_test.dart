import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';
import 'package:streampulse/features/auth/presentation/screens/register_screen.dart';
import 'package:streampulse/app/theme.dart';

class _NullStore implements TokenStore {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier()
      : super(
          AuthRepository(Dio()),
          AuthLocalSource(SecureStorageService(store: _NullStore())),
        ) {
    state = const AuthUnauthenticated();
  }

  ApiException? errorToThrow;
  final calls = <Map<String, String>>[];

  @override
  Future<void> register({
    required String username,
    required String email,
    required String password,
    required bool acceptedTerms,
  }) async {
    calls.add({
      'username': username,
      'email': email,
      'password': password,
      'acceptedTerms': acceptedTerms.toString(),
    });
    if (errorToThrow != null) {
      state = AuthError(message: errorToThrow!.message);
      return;
    }
    state = AuthAuthenticated(
      user: UserModel(id: 'u1', email: email, username: username, role: 'listener'),
      token: 'token',
    );
  }
}

Future<_FakeAuthNotifier> _pump(WidgetTester tester) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  // Le formulaire est plus long que les 800x600 par defaut du banc de test.
  tester.view.physicalSize = const Size(400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final notifier = _FakeAuthNotifier();

  final router = GoRouter(
    initialLocation: '/register',
    routes: [
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(path: '/login', builder: (c, s) => const Text('Login screen')),
      GoRoute(path: '/streams', builder: (c, s) => const Text('Streams screen')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith((ref) => notifier)],
      child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
    ),
  );
  await tester.pump();
  return notifier;
}

final Finder _submitButton = find.descendant(
  of: find.byType(MaterialButton),
  matching: find.text('Create Account'),
);

void main() {
  testWidgets('valide les champs et refuse un formulaire vide', (tester) async {
    final notifier = await _pump(tester);

    await tester.tap(_submitButton);
    await tester.pump();

    expect(find.text('Username is required'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(find.text('Please confirm your password'), findsOneWidget);
    expect(find.text('Vous devez accepter les conditions d\'utilisation'), findsOneWidget);
    expect(notifier.calls, isEmpty);
  });

  testWidgets('refuse des mots de passe qui ne correspondent pas', (tester) async {
    await _pump(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Choose a username'), 'alice');
    await tester.enterText(find.widgetWithText(TextFormField, 'name@example.com'), 'alice@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Create a password'), 'password1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm your password'), 'password2');
    await tester.tap(_submitButton);
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('soumet le formulaire valide et navigue vers /streams', (tester) async {
    final notifier = await _pump(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Choose a username'), 'alice');
    await tester.enterText(find.widgetWithText(TextFormField, 'name@example.com'), 'alice@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Create a password'), 'password1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm your password'), 'password1');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(_submitButton);
    await tester.pumpAndSettle();

    expect(notifier.calls.single, {
      'username': 'alice',
      'email': 'alice@example.com',
      'password': 'password1',
      'acceptedTerms': 'true',
    });
    expect(find.text('Streams screen'), findsOneWidget);
  });

  testWidgets('une erreur API affiche un snackbar et reste sur l\'ecran', (tester) async {
    final notifier = await _pump(tester);
    notifier.errorToThrow = const ApiException(message: 'Email already used');

    await tester.enterText(find.widgetWithText(TextFormField, 'Choose a username'), 'alice');
    await tester.enterText(find.widgetWithText(TextFormField, 'name@example.com'), 'alice@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Create a password'), 'password1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm your password'), 'password1');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(_submitButton);
    await tester.pump();

    expect(find.text('Email already used'), findsOneWidget);
    expect(find.text('Streams screen'), findsNothing);
  });

  testWidgets('la fleche retour renvoie vers /login', (tester) async {
    await _pump(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Login screen'), findsOneWidget);
  });

  testWidgets('le lien "Sign In" renvoie vers /login', (tester) async {
    await _pump(tester);

    await tester.tap(find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('Sign In'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Login screen'), findsOneWidget);
  });

  testWidgets('les boutons oeil basculent la visibilite des mots de passe', (tester) async {
    await _pump(tester);

    Finder passwordEditable() => find.descendant(
          of: find.widgetWithText(TextFormField, 'Create a password'),
          matching: find.byType(EditableText),
        );

    expect(tester.widget<EditableText>(passwordEditable()).obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_off).first);
    await tester.pump();

    expect(tester.widget<EditableText>(passwordEditable()).obscureText, isFalse);
  });
}
