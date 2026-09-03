// Widget tests de BroadcasterScreen (console diffuseur v1-console) :
// creation de stream, liste de ses streams (Go Live / Gerer), console
// a l'antenne (stats, bouton "couper l'antenne" a maintien de 2 s),
// bibliotheque musicale.
//
// Le plugin natif `record` est simule via son MethodChannel
// 'com.llfbandit.record/messages'. IMPORTANT : aucun test ne demarre de
// vrai flux micro (micGranted=false des qu'on passe a l'antenne) — arreter
// un flux record actif sous le fake-async de testWidgets pend de facon
// aleatoire (les awaits de cancel/stop du plugin ne se resolvent jamais et
// gelent le test 10 min). La diffusion micro reelle (record + POST chunke)
// n'est donc pas exercee ici.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';

import 'package:streampulse/app/theme.dart';
import 'package:streampulse/core/network/api_exceptions.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/core/storage/token_store.dart';
import 'package:streampulse/features/auth/data/auth_local_source.dart';
import 'package:streampulse/features/auth/data/auth_repository.dart';
import 'package:streampulse/features/auth/domain/auth_state.dart';
import 'package:streampulse/features/auth/domain/user_model.dart';
import 'package:streampulse/features/auth/presentation/providers/auth_provider.dart';
import 'package:streampulse/features/music/data/music_repository.dart';
import 'package:streampulse/features/music/domain/music_model.dart';
import 'package:streampulse/features/streams/data/stream_repository.dart';
import 'package:streampulse/features/streams/domain/stream_model.dart';
import 'package:streampulse/features/streams/presentation/screens/broadcaster_screen.dart';

class _MockStreamRepository extends Mock implements StreamRepository {}

class _MockMusicRepository extends Mock implements MusicRepository {}

class _NullStore implements TokenStore {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier()
      : super(
          AuthRepository(Dio()),
          AuthLocalSource(SecureStorageService(store: _NullStore())),
        ) {
    state = const AuthAuthenticated(
      user: UserModel(
          id: 'u1',
          email: 'b@example.com',
          username: 'bob',
          role: 'broadcaster'),
      token: 't',
    );
  }
}

StreamModel _stream({
  String id = 's1',
  String title = 'My Show',
  String ownerId = 'u1',
  bool live = false,
  int listeners = 0,
}) =>
    StreamModel(
      id: id,
      title: title,
      description: '',
      ownerId: ownerId,
      status: live ? 'live' : 'created',
      listenerCount: listeners,
      format: 'mp3',
      createdAt: DateTime(2026),
    );

MusicModel _music({String id = 'm1', String title = 'Track', String artist = 'Artist'}) =>
    MusicModel(
      id: id,
      title: title,
      artist: artist,
      album: '',
      duration: 90,
      url: 'https://cdn/$id.mp3',
      uploadedBy: 'u1',
      createdAt: DateTime(2026),
    );

void main() {
  late _MockStreamRepository streamRepo;
  late _MockMusicRepository musicRepo;

  // Pilote le mock du plugin record.
  var micGranted = true;

  const recordChannel = MethodChannel('com.llfbandit.record/messages');

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    streamRepo = _MockStreamRepository();
    musicRepo = _MockMusicRepository();
    micGranted = true;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(recordChannel, (call) async {
      final args = (call.arguments as Map).cast<String, dynamic>();
      final recorderId = args['recorderId'] as String;
      switch (call.method) {
        case 'create':
          // Canal d'etat ecoute par le recorder des sa creation.
          messenger.setMockStreamHandler(
            EventChannel('com.llfbandit.record/events/$recorderId'),
            MockStreamHandler.inline(onListen: (_, __) {}),
          );
          return null;
        case 'hasPermission':
          return micGranted;
        default:
          // stop, dispose, cancel...
          return null;
      }
    });

    when(() => streamRepo.listStreams()).thenAnswer((_) async => []);
    when(() => musicRepo.listMusic()).thenAnswer((_) async => []);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
  });

  Future<void> pumpBroadcaster(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          streamRepositoryProvider.overrideWithValue(streamRepo),
          musicRepositoryProvider.overrideWithValue(musicRepo),
          secureStorageProvider.overrideWithValue(
              SecureStorageService(store: _NullStore())),
          authProvider.overrideWith((ref) => _FakeAuthNotifier()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const BroadcasterScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settleSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
  }

  // Passe a l'antenne sur 'live-1' (possede par u1), sans capture micro
  // (permission refusee) : la console plein ecran s'affiche quand meme.
  Future<void> goLive(WidgetTester tester, {int listeners = 2}) async {
    micGranted = false;
    when(() => streamRepo.listStreams()).thenAnswer((_) async =>
        [_stream(id: 'live-1', title: 'My Show')]);
    when(() => streamRepo.startStream('live-1')).thenAnswer((_) async {});
    when(() => streamRepo.getStream('live-1')).thenAnswer((_) async =>
        _stream(id: 'live-1', title: 'My Show', live: true, listeners: listeners));

    await pumpBroadcaster(tester);
    await tester.pump();

    await tester.tap(find.text('Go Live'));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  group('rendu initial', () {
    testWidgets('la fleche retour revient a l ecran precedent',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            streamRepositoryProvider.overrideWithValue(streamRepo),
            musicRepositoryProvider.overrideWithValue(musicRepo),
            secureStorageProvider.overrideWithValue(
                SecureStorageService(store: _NullStore())),
            authProvider.overrideWith((ref) => _FakeAuthNotifier()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const BroadcasterScreen()),
                    ),
                    child: const Text('Ouvrir'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Console diffuseur'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Ouvrir'), findsOneWidget);
    });

    testWidgets('formulaire + listes vides', (tester) async {
      await pumpBroadcaster(tester);
      await tester.pump();

      expect(find.text('Create New Stream'), findsOneWidget);
      expect(find.text('Your Streams'), findsOneWidget);
      expect(find.text('No streams yet.'), findsOneWidget);
      expect(find.text('Music Library'), findsOneWidget);
      expect(find.text('Add Music'), findsOneWidget);
      expect(find.text('No music uploaded yet.'), findsOneWidget);
    });

    testWidgets('spinners pendant les chargements', (tester) async {
      when(() => streamRepo.listStreams())
          .thenAnswer((_) => Completer<List<StreamModel>>().future);
      when(() => musicRepo.listMusic())
          .thenAnswer((_) => Completer<List<MusicModel>>().future);

      await pumpBroadcaster(tester);

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('erreur de chargement des streams', (tester) async {
      when(() => streamRepo.listStreams())
          .thenAnswer((_) async => throw const ApiException(message: 'boom'));

      await pumpBroadcaster(tester);
      await tester.pump();

      expect(find.textContaining('Error:'), findsOneWidget);
    });
  });

  group('creation de stream', () {
    testWidgets('le titre est obligatoire', (tester) async {
      await pumpBroadcaster(tester);
      await tester.pump();

      await tester.tap(find.text('Create Stream'));
      await tester.pump();

      expect(find.text('Title is required'), findsOneWidget);
    });

    testWidgets('creation reussie avec format choisi', (tester) async {
      when(() => streamRepo.createStream(
            title: any(named: 'title'),
            description: any(named: 'description'),
            format: any(named: 'format'),
          )).thenAnswer((_) async => _stream());

      await pumpBroadcaster(tester);
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Stream Title'), 'Matinale');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Description'), 'Le reveil');
      await tester.tap(find.text('MP3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AAC').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Stream'));
      await tester.pump();
      await tester.pump();

      verify(() => streamRepo.createStream(
          title: 'Matinale', description: 'Le reveil', format: 'aac')).called(1);
      expect(find.text('Stream created'), findsOneWidget);
      await settleSnackBar(tester);
    });

    testWidgets('echec de creation affiche l erreur', (tester) async {
      when(() => streamRepo.createStream(
            title: any(named: 'title'),
            description: any(named: 'description'),
            format: any(named: 'format'),
          )).thenAnswer(
          (_) async => throw const ApiException(message: 'quota'));

      await pumpBroadcaster(tester);
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Stream Title'), 'Matinale');
      await tester.tap(find.text('Create Stream'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Failed to create stream'), findsOneWidget);
      await settleSnackBar(tester);
    });
  });

  group('liste de ses streams', () {
    testWidgets('ne montre que les streams du broadcaster connecte',
        (tester) async {
      when(() => streamRepo.listStreams()).thenAnswer((_) async => [
            _stream(id: 's1', title: 'Mon direct', live: true, listeners: 7),
            _stream(id: 's2', title: 'Mon brouillon'),
            _stream(id: 's3', title: 'Pas a moi', ownerId: 'autre'),
          ]);

      await pumpBroadcaster(tester);
      await tester.pump();

      expect(find.text('Mon direct'), findsOneWidget);
      expect(find.text('Mon brouillon'), findsOneWidget);
      expect(find.text('Pas a moi'), findsNothing);
      // Live : badge + auditeurs + bouton Gerer ; brouillon : Go Live.
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Gérer'), findsOneWidget);
      expect(find.text('Go Live'), findsOneWidget);
    });
  });

  group('console a l antenne', () {
    testWidgets('go live ouvre la console (permission micro refusee)',
        timeout: const Timeout(Duration(seconds: 60)), (tester) async {
      await goLive(tester);

      // Console plein ecran : le formulaire laisse la place a l'antenne.
      expect(find.text('CONSOLE DIFFUSEUR'), findsOneWidget);
      expect(find.text('My Show'), findsOneWidget);
      expect(find.text('AUDITEURS'), findsOneWidget);
      expect(find.text('5 DERN. MIN'), findsOneWidget);
      expect(find.text('COUPURES'), findsOneWidget);
      expect(find.text("Couper l'antenne"), findsOneWidget);
      expect(find.text('Create New Stream'), findsNothing);
      // Pas de capture micro -> statut connexion en attente.
      expect(find.text('ENVOI · CONNEXION…'), findsOneWidget);
      // showSnackBar remplace le snackbar courant : 'Microphone permission
      // denied' est aussitot masque par 'You are LIVE!'.
      expect(find.text('You are LIVE!'), findsOneWidget);
      await settleSnackBar(tester);
    });

    testWidgets('le compteur d auditeurs se rafraichit et le delta apparait',
        timeout: const Timeout(Duration(seconds: 60)), (tester) async {
      await goLive(tester, listeners: 5);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('—'), findsOneWidget); // historique trop court

      // Tick 1 : premiere entree d'historique.
      when(() => streamRepo.getStream('live-1')).thenAnswer((_) async =>
          _stream(id: 'live-1', live: true, listeners: 8));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('8'), findsOneWidget);

      // Tick 2 : delta = courant - premiere entree = 12 - 8.
      when(() => streamRepo.getStream('live-1')).thenAnswer((_) async =>
          _stream(id: 'live-1', live: true, listeners: 12));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('12'), findsOneWidget);
      expect(find.text('+4'), findsOneWidget);
      await settleSnackBar(tester);
    });

    testWidgets('maintenir 2 s coupe l antenne et rend la main',
        timeout: const Timeout(Duration(seconds: 60)), (tester) async {
      when(() => streamRepo.stopStream('live-1')).thenAnswer((_) async {});
      await goLive(tester);
      // Vide le snackbar courant ET la file (clearSnackBars est immediat) :
      // sinon 'Stream stopped' resterait en attente derriere 'You are LIVE!'.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(
          find.bySemanticsLabel("Couper l'antenne, maintenir 2 secondes")));
      // Laisse l'arbitrage des gestes declencher onTapDown (deadline ~100 ms)
      // avant de derouler les 2 s de maintien.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      await gesture.up();
      // Laisse l'animation d'entree du snackbar se jouer.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => streamRepo.stopStream('live-1')).called(1);
      expect(find.text('Stream stopped'), findsOneWidget);
      expect(find.text('Create New Stream'), findsOneWidget);
      await settleSnackBar(tester);
    });

    testWidgets('un maintien relache trop tot ne coupe pas l antenne',
        timeout: const Timeout(Duration(seconds: 60)), (tester) async {
      when(() => streamRepo.stopStream('live-1')).thenAnswer((_) async {});
      await goLive(tester);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(
          find.bySemanticsLabel("Couper l'antenne, maintenir 2 secondes")));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 800));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));

      verifyNever(() => streamRepo.stopStream(any()));
      expect(find.text('CONSOLE DIFFUSEUR'), findsOneWidget);
    });

    testWidgets('Gerer rejoint un direct et relance la capture micro',
        timeout: const Timeout(Duration(seconds: 60)), (tester) async {
      // Permission refusee : on verifie que le micro est demande, sans
      // demarrer un vrai flux record (voir l'en-tete du fichier).
      micGranted = false;
      when(() => streamRepo.listStreams()).thenAnswer((_) async =>
          [_stream(id: 'live-1', title: 'Deja live', live: true, listeners: 3)]);

      await pumpBroadcaster(tester);
      await tester.pump();

      await tester.tap(find.text('Gérer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('CONSOLE DIFFUSEUR'), findsOneWidget);
      expect(find.text('Deja live'), findsOneWidget);
      // Rejoindre ne redemarre pas le flux serveur (deja live)...
      verifyNever(() => streamRepo.startStream(any()));
      // ...mais relance la capture micro : un flux live sans micro dans
      // cette instance de l'app etait un direct muet pour les auditeurs.
      expect(find.text('Microphone permission denied'), findsOneWidget);
      // Le flux est deja en direct cote serveur : "a l'antenne" affiche,
      // sans capture locale tant que la permission manque.
      expect(find.text('ENVOI · CONNEXION…'), findsOneWidget);
      await settleSnackBar(tester);
    });

    testWidgets('echec du demarrage affiche l erreur', (tester) async {
      when(() => streamRepo.listStreams()).thenAnswer(
          (_) async => [_stream(id: 'live-1', title: 'My Show')]);
      when(() => streamRepo.startStream('live-1')).thenAnswer(
          (_) async => throw const ApiException(message: 'deja live'));

      await pumpBroadcaster(tester);
      await tester.pump();

      await tester.tap(find.text('Go Live'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Failed to start'), findsOneWidget);
      expect(find.text('Create New Stream'), findsOneWidget);
      await settleSnackBar(tester);
    });

    testWidgets('echec de l arret affiche l erreur',
        timeout: const Timeout(Duration(seconds: 60)), (tester) async {
      when(() => streamRepo.stopStream('live-1')).thenAnswer(
          (_) async => throw const ApiException(message: 'timeout'));
      await goLive(tester);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pump();

      final gesture = await tester.startGesture(tester.getCenter(
          find.bySemanticsLabel("Couper l'antenne, maintenir 2 secondes")));
      // Laisse l'arbitrage des gestes declencher onTapDown (deadline ~100 ms)
      // avant de derouler les 2 s de maintien.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      await gesture.up();
      // Laisse l'animation d'entree du snackbar se jouer.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => streamRepo.stopStream('live-1')).called(1);
      expect(find.textContaining('Failed to stop'), findsOneWidget);
      await settleSnackBar(tester);
    });
  });

  group('bibliotheque musicale', () {
    testWidgets('affiche les pistes et artiste inconnu', (tester) async {
      when(() => musicRepo.listMusic()).thenAnswer((_) async => [
            _music(id: 'm1', title: 'Nocturne', artist: 'Chopin'),
            _music(id: 'm2', title: 'Mystere', artist: ''),
          ]);

      await pumpBroadcaster(tester);
      await tester.pump();

      expect(find.text('Nocturne'), findsOneWidget);
      expect(find.text('Chopin'), findsOneWidget);
      expect(find.text('Mystere'), findsOneWidget);
      expect(find.text('Unknown artist'), findsOneWidget);
    });

    testWidgets('le bouton refresh recharge la musique', (tester) async {
      await pumpBroadcaster(tester);
      await tester.pump();
      expect(find.text('No music uploaded yet.'), findsOneWidget);

      when(() => musicRepo.listMusic())
          .thenAnswer((_) async => [_music(title: 'Nouveau son')]);
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      await tester.pump();

      expect(find.text('Nouveau son'), findsOneWidget);
      verify(() => musicRepo.listMusic()).called(2);
    });

    testWidgets('le dialog Add Music valide ses champs', (tester) async {
      await pumpBroadcaster(tester);
      await tester.pump();

      await tester.tap(find.text('Add Music'));
      await tester.pumpAndSettle();
      expect(find.text('Add Music by URL'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pump();

      expect(find.text('URL is required'), findsOneWidget);
      expect(find.text('Title is required'), findsOneWidget);
      expect(find.text('Artist is required'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Add Music by URL'), findsNothing);
    });

    testWidgets('ajout d une piste par URL reussi', (tester) async {
      when(() => musicRepo.addMusicByUrl(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            url: any(named: 'url'),
            duration: any(named: 'duration'),
          )).thenAnswer((_) async => _music());

      await pumpBroadcaster(tester);
      await tester.pump();

      await tester.tap(find.text('Add Music'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Audio URL'),
          'https://cdn/son.mp3');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Title'), 'Son');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Artist'), 'Moi');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Duration (seconds)'), '180');

      await tester.tap(find.text('Add'));
      // Laisse l'animation de fermeture du dialog se terminer.
      await tester.pumpAndSettle();

      verify(() => musicRepo.addMusicByUrl(
          title: 'Son',
          artist: 'Moi',
          album: '',
          url: 'https://cdn/son.mp3',
          duration: 180)).called(1);
      expect(find.text('Add Music by URL'), findsNothing);
      expect(find.text('Music added successfully'), findsOneWidget);
      await settleSnackBar(tester);
    });

    testWidgets('echec d ajout laisse le dialog ouvert', (tester) async {
      when(() => musicRepo.addMusicByUrl(
            title: any(named: 'title'),
            artist: any(named: 'artist'),
            album: any(named: 'album'),
            url: any(named: 'url'),
            duration: any(named: 'duration'),
          )).thenAnswer(
          (_) async => throw const ApiException(message: 'format'));

      await pumpBroadcaster(tester);
      await tester.pump();

      await tester.tap(find.text('Add Music'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Audio URL'),
          'https://cdn/son.mp3');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Title'), 'Son');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Artist'), 'Moi');

      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Add Music by URL'), findsOneWidget);
      expect(find.textContaining('Failed to add music'), findsOneWidget);
      await settleSnackBar(tester);
    });
  });
}
