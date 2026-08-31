import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/theme.dart';
import 'app/web_router.dart';

/// Entry point for the broadcaster/admin web console.
///
/// Build it with:
///   flutter build web -t lib/main_web.dart --dart-define=API_BASE_URL=...
///
/// The mobile app keeps `lib/main.dart` as its entry point; the two share the
/// data, domain and design-system layers but not the navigation graph.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: StreamPulseConsoleApp(),
    ),
  );
}

class StreamPulseConsoleApp extends ConsumerWidget {
  const StreamPulseConsoleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(webRouterProvider);

    return MaterialApp.router(
      title: 'StreamPulse Console',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
