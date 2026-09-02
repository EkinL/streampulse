import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/audio/audio_handler.dart';
import 'shared/providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    // Le rendu CanvasKit ne construit pas l'arbre semantique par defaut :
    // sans cet appel, les lecteurs d'ecran ne voient qu'un canevas vide.
    // Sur mobile, VoiceOver/TalkBack l'activent eux-memes a la demande.
    SemanticsBinding.instance.ensureSemantics();
  }
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
    final themeMode = ref.watch(themeModeProvider);
    final highContrast = ref.watch(highContrastProvider);
    final textScaleFactor = ref.watch(textScaleProvider).factor;

    return MaterialApp.router(
      title: 'StreamPulse',
      debugShowCheckedModeBanner: false,
      theme: highContrast ? AppTheme.lightHighContrastTheme : AppTheme.lightTheme,
      darkTheme: highContrast ? AppTheme.darkHighContrastTheme : AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        if (textScaleFactor == null || child == null) return child ?? const SizedBox.shrink();
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child,
        );
      },
    );
  }
}
