import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/streams/presentation/providers/live_stream_provider.dart';
import 'package:streampulse/features/streams/presentation/widgets/audio_player_bar.dart';
import 'package:streampulse/app/theme.dart';

class _NullStore implements TokenStore {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _FakeLiveStreamNotifier extends LiveStreamNotifier {
  _FakeLiveStreamNotifier() : super(SecureStorageService(store: _NullStore()));

  void setTestState(LiveStreamState newState) => state = newState;
}

Future<_FakeLiveStreamNotifier> _pump(
  WidgetTester tester, {
  required String streamId,
  bool isLive = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final liveNotifier = _FakeLiveStreamNotifier();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [liveStreamProvider.overrideWith((ref) => liveNotifier)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: AudioPlayerBar(title: 'Night Show', streamId: streamId, isLive: isLive),
        ),
      ),
    ),
  );
  await tester.pump();
  return liveNotifier;
}

void main() {
  testWidgets('affiche le bouton play quand rien n\'est connecte', (tester) async {
    // Apres le premier pump, le callback post-frame de la barre a deja
    // signale le stream comme "live" via onStreamLive : le texte reflete ce
    // second etat, pas le texte par defaut du tout premier rendu.
    await _pump(tester, streamId: 's1');

    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
    expect(find.text('Stream is live! Tap to listen'), findsOneWidget);
  });

  testWidgets('bouton play desactive quand le stream n\'est pas en direct', (tester) async {
    await _pump(tester, streamId: 's1', isLive: false);

    final icon = tester.widget<Icon>(find.byIcon(Icons.play_circle_filled));
    expect((icon.color as Color).a, closeTo(0.3, 0.01));
  });

  testWidgets('affiche un spinner pendant la connexion', (tester) async {
    final liveNotifier = await _pump(tester, streamId: 's1');
    liveNotifier.setTestState(const LiveStreamState(streamId: 's1', isConnecting: true));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche waveform, statut et volume quand connecte', (tester) async {
    final liveNotifier = await _pump(tester, streamId: 's1');
    liveNotifier.setTestState(
      const LiveStreamState(streamId: 's1', isConnected: true, isReceivingData: true, statusText: 'Connected'),
    );
    await tester.pump();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.byType(Semantics), findsWidgets);
    final semantics = tester.widgetList<Semantics>(find.byType(Semantics)).where((s) => s.properties.label == 'Stop listening');
    expect(semantics, isNotEmpty);
  });

  testWidgets('tap sur le bouton stop appelle disconnect', (tester) async {
    final liveNotifier = await _pump(tester, streamId: 's1');
    liveNotifier.setTestState(const LiveStreamState(streamId: 's1', isConnected: true));
    await tester.pump();

    await tester.tap(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Stop listening'));
    await tester.pump();

    expect(liveNotifier.state.isConnected, isFalse);
  });

  testWidgets('un flux connecte pour un autre stream n\'affiche pas l\'etat connecte', (tester) async {
    final liveNotifier = await _pump(tester, streamId: 's1');
    liveNotifier.setTestState(const LiveStreamState(streamId: 's2', isConnected: true));
    await tester.pump();

    expect(find.text('Tap play to listen'), findsOneWidget);
  });

  testWidgets('le meme stream redevenu live remplace le libelle "Stream ended"', (tester) async {
    final liveNotifier = await _pump(tester, streamId: 's1');
    // Etat laisse par une deconnexion : le flux a ete coupe puis redemarre.
    liveNotifier.setTestState(const LiveStreamState(streamId: 's1', statusText: 'Stream ended'));
    await tester.pump(); // rebuild : le callback post-frame signale le retour en live
    await tester.pump(); // applique le nouvel etat

    expect(find.text('Stream ended'), findsNothing);
    expect(find.text('Stream is live! Tap to listen'), findsOneWidget);
  });
}
