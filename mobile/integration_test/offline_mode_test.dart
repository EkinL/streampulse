import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import 'package:streampulse/app/constants.dart';
import 'package:streampulse/core/audio/audio_handler.dart';
import 'package:streampulse/core/storage/offline_audio_store.dart';
import 'package:streampulse/features/music/domain/music_model.dart';
import 'package:streampulse/shared/providers/offline_provider.dart';
import 'package:streampulse/shared/providers/player_provider.dart';

/// Test de bout en bout du mode offline, sur simulateur/appareil, avec le
/// backend qui tourne sur la machine hote (http://localhost:8080).
///
/// Scenario : telecharger un morceau du catalogue (vrai Dio, vrai
/// path_provider, vrai disque), puis le jouer via le lecteur avec une URL
/// reseau volontairement morte. Si l'audio demarre, il vient forcement du
/// fichier local : c'est l'ecoute sans reseau.
///
/// Lancer avec : flutter test integration_test/offline_mode_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('telecharge un morceau puis le joue sans reseau',
      (tester) async {
    // 1. Trouver un morceau heberge par notre backend (/uploads).
    final dio = Dio();
    final Response<dynamic> res;
    try {
      res = await dio.get('${AppConstants.apiBaseUrl}/music');
    } on DioException {
      markTestSkipped('backend injoignable sur ${AppConstants.apiBaseUrl} — '
          'demarrer l\'API avant de lancer ce test');
      return;
    }
    final items = ((res.data as Map<String, dynamic>)['data'] as List)
        .cast<Map<String, dynamic>>();
    final uploaded = items.firstWhere(
      (m) => (m['url'] as String).contains('/uploads/'),
      orElse: () => throw StateError(
          'aucun morceau /uploads en base — en uploader un via POST /music'),
    );
    final trackId = uploaded['id'] as String;
    final trackUrl = uploaded['url'] as String;

    // 2. Telechargement sur le disque de l'appareil.
    final store = OfflineAudioStore();
    final offline = OfflineNotifier(store, Dio());
    addTearDown(offline.dispose);
    await offline.downloadTrack(id: trackId, url: trackUrl);

    expect(offline.state.isCached(trackId), isTrue);
    final localPath = await offline.localPathFor(trackId);
    expect(localPath, isNotNull);
    expect(File(localPath!).lengthSync(), greaterThan(0));

    // 3. Lecture avec une URL reseau morte : seul le fichier local peut jouer.
    final handler = StreamPulseAudioHandler();
    addTearDown(handler.dispose);
    final player = PlayerNotifier(
      handler,
      localPathResolver: offline.localPathFor,
    );
    addTearDown(player.dispose);

    final deadTrack = MusicModel(
      id: trackId,
      title: 'Offline test',
      artist: '',
      album: '',
      duration: 0,
      url: 'http://localhost:1/inaccessible.mp3',
      uploadedBy: '',
      createdAt: DateTime(2026),
    );
    final events = <String>[];
    handler.playingStream.listen((p) => events.add('playing=$p'));
    handler.processingStateStream.listen((s) => events.add('proc=$s'));

    // Le futur de play() (just_audio) ne se resout qu'a la fin de la lecture :
    // au retour, le morceau a ete joue en entier.
    final chrono = Stopwatch()..start();
    await player.play(deadTrack);
    chrono.stop();

    expect(events, contains('playing=true'),
        reason: 'le lecteur n\'est jamais passe en lecture — '
            'events: ${events.join(' | ')}');
    expect(events, contains('proc=${ProcessingState.completed}'),
        reason: 'la lecture ne s\'est pas terminee — '
            'events: ${events.join(' | ')}');
    expect(player.state.duration, greaterThan(Duration.zero));
    // Lecture en temps reel, pas un saut instantane a la fin du fichier.
    expect(chrono.elapsed, greaterThan(const Duration(seconds: 1)),
        reason: 'lecture anormalement instantanee (${chrono.elapsed})');

    await player.stop();
  });
}
