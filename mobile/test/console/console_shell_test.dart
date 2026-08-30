import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:streampulse/app/theme.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';
import 'package:streampulse/features/console/presentation/widgets/console_shell.dart';

class _NullStore implements TokenStore {
  @override
  Future<void> delete(String key) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

/// An AuthNotifier parked in [AuthAuthenticated] so the shell can be rendered
/// without touching the network.
class _SignedInNotifier extends AuthNotifier {
  _SignedInNotifier(UserModel user)
      : super(
          AuthRepository(Dio()),
          AuthLocalSource(SecureStorageService(store: _NullStore())),
        ) {
    state = AuthAuthenticated(user: user, token: 'token');
  }
}

UserModel _user(String role) => UserModel(
      id: 'u1',
      email: 'someone@example.com',
      username: 'someone',
      role: role,
    );

Future<void> _pumpShell(
  WidgetTester tester, {
  required String role,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/broadcaster',
    routes: [
      ShellRoute(
        builder: (context, state, child) => ConsoleShell(child: child),
        routes: [
          GoRoute(
            path: '/broadcaster',
            builder: (context, state) => const Placeholder(),
          ),
          GoRoute(
            path: '/admin',
            builder: (context, state) => const Placeholder(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _SignedInNotifier(_user(role))),
      ],
      child: MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('wide viewport shows the labelled sidebar', (tester) async {
    await _pumpShell(tester, role: 'admin', size: const Size(1400, 900));

    expect(find.text('CONSOLE'), findsOneWidget);
    expect(find.text('Broadcast'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Go live and manage your streams'), findsOneWidget);
    expect(find.text('someone'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('narrow viewport collapses to an icon rail', (tester) async {
    await _pumpShell(tester, role: 'admin', size: const Size(800, 900));

    // Labels and the user card give way to icons with tooltips.
    expect(find.text('CONSOLE'), findsNothing);
    expect(find.text('Broadcast'), findsNothing);
    expect(find.text('Sign out'), findsNothing);
    expect(find.byIcon(Icons.podcasts), findsOneWidget);
    expect(find.byIcon(Icons.admin_panel_settings_outlined), findsOneWidget);
  });

  testWidgets('a broadcaster gets no Users section', (tester) async {
    await _pumpShell(tester, role: 'broadcaster', size: const Size(1400, 900));

    expect(find.text('Broadcast'), findsOneWidget);
    expect(find.text('Users'), findsNothing);
  });
}
