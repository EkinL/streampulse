import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/admin/presentation/screens/admin_users_screen.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/console/presentation/screens/console_denied_screen.dart';
import '../features/console/presentation/screens/console_login_screen.dart';
import '../features/console/presentation/widgets/console_shell.dart';
import '../features/streams/presentation/screens/broadcaster_screen.dart';
import 'theme.dart';

class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(AuthState initial) : _authState = initial;

  AuthState _authState;
  AuthState get authState => _authState;

  void update(AuthState newState) {
    _authState = newState;
    notifyListeners();
  }
}

/// Router for the web console.
///
/// Only the broadcaster and admin sections are reachable here — listening,
/// playlists, favorites and search stay in the mobile app. Every route is
/// gated on the signed-in user's role.
final webRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref.read(authProvider));

  ref.listen<AuthState>(authProvider, (_, next) => notifier.update(next));

  final router = GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = notifier.authState;
      final path = state.uri.path;

      // Still restoring the session. Park on the splash, but remember where
      // the user was heading so a reload or bookmark is not lost.
      if (authState is AuthLoading) {
        if (path == '/splash') return null;
        return Uri(path: '/splash', queryParameters: {'from': path}).toString();
      }

      if (authState is! AuthAuthenticated) {
        return path == '/login' ? null : '/login';
      }

      final destinations = destinationsFor(authState.user);

      // A listener has no console section at all.
      if (destinations.isEmpty) {
        return path == '/denied' ? null : '/denied';
      }

      final allowed = destinations.map((d) => d.path).toSet();
      if (allowed.contains(path)) return null;

      // Coming off the splash: honour the remembered destination when the
      // user's role allows it.
      if (path == '/splash') {
        final from = state.uri.queryParameters['from'];
        if (from != null && allowed.contains(from)) return from;
      }

      return destinations.first.path;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const ConsoleLoginScreen(),
      ),
      GoRoute(
        path: '/denied',
        builder: (context, state) => const ConsoleDeniedScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ConsoleShell(child: child),
        routes: [
          GoRoute(
            path: '/broadcaster',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: BroadcasterScreen()),
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AdminUsersScreen()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: SP.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: SP.text3),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/splash'),
              child: const Text('Back to console'),
            ),
          ],
        ),
      ),
    ),
  );

  ref.onDispose(router.dispose);
  ref.onDispose(notifier.dispose);

  return router;
});
