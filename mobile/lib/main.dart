import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/audio/audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await _initAudio();
  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const StreamPulseApp(),
    ),
  );
}

Future<StreamPulseAudioHandler> _initAudio() async {
  StreamPulseAudioHandler handler;
  try {
    handler = await AudioService.init(
      builder: StreamPulseAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.streampulse.playback',
        androidNotificationChannelName: 'StreamPulse - lecture',
        androidNotificationChannelDescription:
            'Controles de lecture et maintien du flux audio en arriere-plan',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    // pas de session media (desktop, tests) : lecture sans notification
    debugPrint('audio_service indisponible: $e');
    handler = StreamPulseAudioHandler();
  }
  try {
    await handler.init();
  } catch (e) {
    debugPrint('session audio non configuree: $e');
  }
  return handler;
}

class StreamPulseApp extends ConsumerWidget {
  const StreamPulseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'StreamPulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
