import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/register_screen.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/streams/presentation/screens/streams_list_screen.dart';
import '../features/streams/presentation/screens/stream_detail_screen.dart';
import '../features/streams/presentation/screens/broadcaster_screen.dart';
import '../features/playlists/presentation/screens/playlists_screen.dart';
import '../features/playlists/presentation/screens/playlist_detail_screen.dart';
import '../features/favorites/presentation/screens/favorites_screen.dart';
import '../features/admin/presentation/screens/admin_users_screen.dart';
import '../shared/widgets/app_scaffold.dart';
import '../features/music/presentation/screens/search_screen.dart';
import '../features/music/presentation/screens/music_player_screen.dart';

class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(AuthState initial) : _authState = initial;

  AuthState _authState;
  AuthState get authState => _authState;

  void update(AuthState newState) {
    _authState = newState;
    notifyListeners();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref.read(authProvider));

  ref.listen<AuthState>(authProvider, (_, next) => notifier.update(next));

  final router = GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = notifier.authState;
      final isAuthenticated = authState is AuthAuthenticated;
      final isLoading = authState is AuthLoading;
      final currentPath = state.uri.toString();

      final authPaths = ['/login', '/register'];
      final isOnAuthPath = authPaths.contains(currentPath);
      final isOnSplash = currentPath == '/splash';

      // Stay on splash only while loading
      if (isLoading) {
        return isOnSplash ? null : '/splash';
      }

      // Done loading: leave splash immediately
      if (isOnSplash) {
        return isAuthenticated ? '/streams' : '/login';
      }

      // Not authenticated: redirect to login
      if (!isAuthenticated && !isOnAuthPath) {
        return '/login';
      }

      // Authenticated but on auth page: go to streams
      if (isAuthenticated && isOnAuthPath) {
        return '/streams';
      }

      // Admin guard
      if (currentPath.startsWith('/admin')) {
        if (isAuthenticated && !authState.user.isAdmin) {
          return '/streams';
        }
      }

      // Broadcaster guard
      if (currentPath == '/broadcaster') {
        if (isAuthenticated && !authState.user.isBroadcaster) {
          return '/streams';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppScaffold(child: child),
        routes: [
          GoRoute(
            path: '/streams',
            pageBuilder: (context, state) => const NoTransitionPage(child: StreamsListScreen()),
          ),
          GoRoute(
            path: '/playlists',
            pageBuilder: (context, state) => const NoTransitionPage(child: PlaylistsScreen()),
          ),
          GoRoute(
            path: '/favorites',
            pageBuilder: (context, state) => const NoTransitionPage(child: FavoritesScreen()),
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (context, state) => const NoTransitionPage(child: AdminUsersScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/streams/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return StreamDetailScreen(streamId: id);
        },
      ),
      GoRoute(
        path: '/playlists/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PlaylistDetailScreen(playlistId: id);
        },
      ),
      GoRoute(
        path: '/broadcaster',
        builder: (context, state) => const BroadcasterScreen(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) => const MusicPlayerScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/streams'),
              child: const Text('Go Home'),
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
