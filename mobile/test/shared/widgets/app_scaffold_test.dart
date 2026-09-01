import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';
import 'package:streampulse/shared/providers/player_provider.dart';
import 'package:streampulse/shared/widgets/app_scaffold.dart';
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
  _FakeAuthNotifier(UserModel user)
      : super(
          AuthRepository(Dio()),
          AuthLocalSource(SecureStorageService(store: _NullStore())),
        ) {
    state = AuthAuthenticated(user: user, token: 'token');
  }

  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const AuthUnauthenticated();
  }
}

class _FakePlayerHandler extends Fake implements StreamPulseAudioHandler {
  @override
  VoidCallback? onSkipToNext;
  @override
  VoidCallback? onSkipToPrevious;
  @override
  VoidCallback? onLiveStop;

  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override
  Stream<double> get volumeStream => const Stream.empty();
  @override
  Future<void> setVolume(double v) async {}
}

UserModel _user({String role = 'listener'}) => UserModel(
      id: 'u1',
      email: 'alice@example.com',
      username: 'alice',
      role: role,
    );

Future<GoRouter> _pumpScaffold(
  WidgetTester tester, {
  required _FakeAuthNotifier authNotifier,
  String initialLocation = '/streams',
}) async {
  // Taille de telephone : la feuille de profil deborde sur les 800x600 par
  // defaut du banc de test, qui n'ont rien a voir avec un vrai ecran mobile.
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppScaffold(child: child),
        routes: [
          GoRoute(path: '/streams', builder: (c, s) => const Text('Streams screen')),
          GoRoute(path: '/playlists', builder: (c, s) => const Text('Playlists screen')),
          GoRoute(path: '/favorites', builder: (c, s) => const Text('Favorites screen')),
          GoRoute(path: '/profile', builder: (c, s) => const Text('Profile screen')),
          GoRoute(path: '/admin', builder: (c, s) => const Text('Admin screen')),
        ],
      ),
      GoRoute(path: '/login', builder: (c, s) => const Text('Login screen')),
      GoRoute(path: '/account', builder: (c, s) => const Text('Account screen')),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => authNotifier),
        audioHandlerProvider.overrideWithValue(_FakePlayerHandler()),
        playerProvider.overrideWith((ref) => PlayerNotifier(_FakePlayerHandler())),
      ],
      child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  testWidgets('met en avant l\'onglet STREAMS sur /streams', (tester) async {
    await _pumpScaffold(tester, authNotifier: _FakeAuthNotifier(_user()));

    expect(find.byIcon(Icons.radio), findsOneWidget);
    expect(find.byIcon(Icons.radio_outlined), findsNothing);
  });

  testWidgets('met en avant l\'onglet PLAYLISTS sur /playlists', (tester) async {
    await _pumpScaffold(
      tester,
      authNotifier: _FakeAuthNotifier(_user()),
      initialLocation: '/playlists',
    );

    expect(find.byIcon(Icons.queue_music), findsOneWidget);
  });

  testWidgets('n\'affiche pas l\'onglet ADMIN pour un utilisateur non-admin', (tester) async {
    await _pumpScaffold(tester, authNotifier: _FakeAuthNotifier(_user(role: 'listener')));

    expect(find.text('ADMIN'), findsNothing);
  });

  testWidgets('affiche l\'onglet ADMIN pour un administrateur', (tester) async {
    await _pumpScaffold(tester, authNotifier: _FakeAuthNotifier(_user(role: 'admin')));

    expect(find.text('ADMIN'), findsOneWidget);
  });

  testWidgets('tap sur PLAYLISTS navigue vers l\'ecran playlists', (tester) async {
    await _pumpScaffold(tester, authNotifier: _FakeAuthNotifier(_user()));

    await tester.tap(find.text('PLAYLISTS'));
    await tester.pumpAndSettle();

    expect(find.text('Playlists screen'), findsOneWidget);
  });

  testWidgets('tap sur FAVORIS navigue vers l\'ecran favoris', (tester) async {
    await _pumpScaffold(tester, authNotifier: _FakeAuthNotifier(_user()));

    await tester.tap(find.text('FAVORIS'));
    await tester.pumpAndSettle();

    expect(find.text('Favorites screen'), findsOneWidget);
  });

  testWidgets('tap sur ADMIN navigue vers l\'ecran admin', (tester) async {
    await _pumpScaffold(tester, authNotifier: _FakeAuthNotifier(_user(role: 'admin')));

    await tester.tap(find.text('ADMIN'));
    await tester.pumpAndSettle();

    expect(find.text('Admin screen'), findsOneWidget);
  });

  testWidgets('tap sur PROFIL ouvre la feuille avec les infos du compte', (tester) async {
    await _pumpScaffold(tester, authNotifier: _FakeAuthNotifier(_user(role: 'broadcaster')));

    await tester.tap(find.text('PROFIL'));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('BROADCASTER'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);
    expect(find.text('Mon compte'), findsOneWidget);
  });

  testWidgets('Mon compte navigue vers /account', (tester) async {
    await _pumpScaffold(tester, authNotifier: _FakeAuthNotifier(_user()));

    await tester.tap(find.text('PROFIL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon compte'));
    await tester.pumpAndSettle();

    expect(find.text('Account screen'), findsOneWidget);
  });

  testWidgets('Sign Out deconnecte et renvoie vers /login', (tester) async {
    final authNotifier = _FakeAuthNotifier(_user());
    await _pumpScaffold(tester, authNotifier: authNotifier);

    await tester.tap(find.text('PROFIL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    expect(authNotifier.logoutCalls, 1);
    expect(find.text('Login screen'), findsOneWidget);
  });
}
