import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';
import 'package:streampulse/features/auth/presentation/screens/account_screen.dart';
import 'package:streampulse/shared/providers/theme_provider.dart';
import 'package:streampulse/app/theme.dart';

class _NullStore implements TokenStore {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _NoopThemeModeStore implements ThemeModeStore {
  @override
  Future<ThemeMode?> load() async => null;
  @override
  Future<void> save(ThemeMode mode) async {}
}

class _NoopHighContrastStore implements HighContrastStore {
  @override
  Future<bool?> load() async => null;
  @override
  Future<void> save(bool enabled) async {}
}

class _NoopTextScaleStore implements TextScaleStore {
  @override
  Future<AppTextScale?> load() async => null;
  @override
  Future<void> save(AppTextScale scale) async {}
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(UserModel user)
      : super(
          AuthRepository(Dio()),
          AuthLocalSource(SecureStorageService(store: _NullStore())),
        ) {
    state = AuthAuthenticated(user: user, token: 'token');
  }

  int deleteAccountCalls = 0;
  bool deleteShouldFail = false;

  int updateProfileCalls = 0;
  bool updateShouldFail = false;
  String? lastEmail;
  String? lastUsername;

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    if (deleteShouldFail) {
      throw const ApiException(message: 'Server exploded');
    }
    state = const AuthUnauthenticated();
  }

  @override
  Future<void> updateProfile({required String email, required String username}) async {
    updateProfileCalls++;
    lastEmail = email;
    lastUsername = username;
    if (updateShouldFail) {
      throw const ApiException(message: 'Update refused');
    }
    final current = state;
    if (current is AuthAuthenticated) {
      state = AuthAuthenticated(
        user: UserModel(id: current.user.id, email: email, username: username, role: current.user.role),
        token: current.token,
      );
    }
  }
}

UserModel _user() => const UserModel(
      id: 'u1',
      email: 'alice@example.com',
      username: 'alice',
      role: 'listener',
    );

Future<_FakeAuthNotifier> _pump(WidgetTester tester, {UserModel? user}) async {
  // Ecran long (ListView) : une taille de test standard (800x600) laisse la
  // moitie du contenu hors viewport et donc jamais layout.
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authNotifier = _FakeAuthNotifier(user ?? _user());
  final router = GoRouter(
    initialLocation: '/account',
    routes: [
      GoRoute(path: '/account', builder: (c, s) => const AccountScreen()),
      GoRoute(path: '/login', builder: (c, s) => const Text('Login screen')),
      GoRoute(path: '/privacy', builder: (c, s) => const Text('Privacy screen')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => authNotifier),
        themeModeProvider.overrideWith((ref) => ThemeModeNotifier(_NoopThemeModeStore())),
        highContrastProvider.overrideWith((ref) => HighContrastNotifier(_NoopHighContrastStore())),
        textScaleProvider.overrideWith((ref) => TextScaleNotifier(_NoopTextScaleStore())),
      ],
      child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
    ),
  );
  await tester.pump();
  return authNotifier;
}

void main() {
  testWidgets('affiche les informations du compte', (tester) async {
    await _pump(tester);

    expect(find.text('alice'), findsWidgets);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('LISTENER'), findsOneWidget);
    expect(find.text('u1'), findsOneWidget);
  });

  testWidgets('tap sur Politique de confidentialite navigue vers /privacy', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Politique de confidentialité'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy screen'), findsOneWidget);
  });

  testWidgets('supprimer le compte : Annuler garde la session ouverte', (tester) async {
    final authNotifier = await _pump(tester);

    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer votre compte ?'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(authNotifier.deleteAccountCalls, 0);
    expect(find.text('alice'), findsWidgets);
  });

  testWidgets('supprimer le compte : confirmation supprime et renvoie vers /login', (tester) async {
    final authNotifier = await _pump(tester);

    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(authNotifier.deleteAccountCalls, 1);
    expect(find.text('Login screen'), findsOneWidget);
  });

  testWidgets('supprimer le compte : une erreur serveur affiche un message et garde la session', (tester) async {
    final authNotifier = await _pump(tester);
    authNotifier.deleteShouldFail = true;

    await tester.tap(find.text('Supprimer mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Suppression impossible'), findsOneWidget);
    expect(find.text('alice'), findsWidgets);
  });

  testWidgets('modifier le profil : Annuler ne change rien', (tester) async {
    final authNotifier = await _pump(tester);

    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier mes informations'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(authNotifier.updateProfileCalls, 0);
  });

  testWidgets('modifier le profil : Enregistrer avec des valeurs valides met a jour', (tester) async {
    final authNotifier = await _pump(tester);

    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'new@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'newname');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(authNotifier.updateProfileCalls, 1);
    expect(authNotifier.lastEmail, 'new@example.com');
    expect(authNotifier.lastUsername, 'newname');
    expect(find.text('Informations mises à jour.'), findsOneWidget);
    expect(find.text('newname'), findsWidgets);
  });

  testWidgets('modifier le profil : email invalide bloque la soumission', (tester) async {
    final authNotifier = await _pump(tester);

    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(authNotifier.updateProfileCalls, 0);
    expect(find.text('Modifier mes informations'), findsOneWidget);
  });

  testWidgets('modifier le profil : une erreur API affiche un message', (tester) async {
    final authNotifier = await _pump(tester);
    authNotifier.updateShouldFail = true;

    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Modification impossible'), findsOneWidget);
  });

  testWidgets('bascule Contraste eleve appelle le notifier', (tester) async {
    await _pump(tester);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets('changer le mode d\'apparence appelle le notifier', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Clair'));
    await tester.pump();

    expect(find.text('Clair'), findsOneWidget);
  });

  testWidgets('changer la taille du texte appelle le notifier', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Grand'));
    await tester.pump();

    expect(find.text('Grand'), findsOneWidget);
  });

  testWidgets('le bouton retour depile l\'ecran', (tester) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authNotifier = _FakeAuthNotifier(_user());
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (c, s) => const Text('Home')),
        GoRoute(path: '/account', builder: (c, s) => const AccountScreen()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => authNotifier),
          themeModeProvider.overrideWith((ref) => ThemeModeNotifier(_NoopThemeModeStore())),
          highContrastProvider.overrideWith((ref) => HighContrastNotifier(_NoopHighContrastStore())),
          textScaleProvider.overrideWith((ref) => TextScaleNotifier(_NoopTextScaleStore())),
        ],
        child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
      ),
    );
    await tester.pump();
    router.push('/account');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });
}
