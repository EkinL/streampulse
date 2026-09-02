# ADR 004: Lecture en arriere-plan avec audio_service

## Statut
Accepted

## Contexte
Le lecteur doit continuer a jouer quand l'app passe en arriere-plan et gerer les interruptions (appel, autre app audio, casque debranche). Sans configuration, iOS suspend l'app quelques secondes apres sa mise en arriere-plan et Android tue le process des qu'il manque de memoire.

Deux sources audio de nature differente cohabitent :
- les pistes (musiques, playlists), lues par `just_audio` depuis une URL
- le live, du PCM brut recu en HTTP et pousse dans `flutter_sound` (voir ADR 003)

## Decision
Utiliser **audio_service** avec un handler unique (`StreamPulseAudioHandler`, injecte par Riverpod) enregistre au demarrage via `AudioService.init`.

- Android : foreground service de type `mediaPlayback` avec notification media, `MainActivity` etend `AudioServiceActivity` pour partager le `FlutterEngine` avec le service. Permissions `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (Android 14+), `WAKE_LOCK`.
- iOS : `UIBackgroundModes = audio`, session `AVAudioSession` en categorie playback.

Le handler a deux modes exclusifs :
- **piste** : il possede l'`AudioPlayer` just_audio et traduit ses evenements en `PlaybackState` (precedent, play/pause, stop, suivant, seek sur l'ecran verrouille). `PlayerNotifier` garde la file d'attente et branche `onSkipToNext` / `onSkipToPrevious`.
- **live** : flutter_sound continue de jouer, le handler declare seulement `playing: true` avec un controle stop, ce qui suffit pour que l'OS maintienne le process. Stop systeme, appel entrant ou casque debranche renvoient a `LiveStreamNotifier.disconnect()`.

Demarrer une source coupe l'autre.

Interruptions (`audio_session`) : duck baisse le volume a 30 % puis le restaure, pause (appel) met en pause et reprend a la fin, `becomingNoisy` met en pause.

Volume : un `volumeProvider` unique (borne [0, 1], persiste en `shared_preferences`) alimente `just_audio.setVolume` et `flutter_sound.setVolume`.

## Alternatives ecartees
- **just_audio_background** : plus simple mais limite au seul `AudioPlayer` de just_audio, le live flutter_sound n'aurait ni maintien en arriere-plan ni bouton stop.
- **Foreground service maison** (Kotlin/Swift) : reinvente audio_service sans les controles ecran verrouille ni l'integration Bluetooth/CarPlay.
- **Migrer le live vers just_audio** : just_audio ne lit pas un flux PCM pousse par l'app.

## Consequences
- Lecture continue ecran eteint, controles depuis la notification, l'ecran verrouille et les ecouteurs.
- `AudioPlayer` est injectable dans le handler, donc testable sans plateforme.
- Un live interrompu par un appel n'est pas reconnecte automatiquement, l'utilisateur relance.
- Sans session media (desktop, tests), `main()` retombe sur un handler local : l'app lit, sans notification.

---

## Summary (English)

Playback must survive backgrounding and handle interruptions (calls,
other audio apps, headphone unplug), across two different audio sources —
tracks played by `just_audio` from a URL, and the live stream, raw PCM
pushed into `flutter_sound`. **audio_service** provides a single handler
(`StreamPulseAudioHandler`, injected via Riverpod) that translates
whichever source is active into a `PlaybackState` for the lock screen and
notification controls; starting one source stops the other. Android runs
a `mediaPlayback`-type foreground service; iOS declares the `audio`
background mode. Volume is a single provider persisted to
`shared_preferences` and applied to both audio engines; interruptions duck
volume to 30%, pause on incoming calls (resuming after), and pause on
`becomingNoisy` (headphones unplugged). Rejected alternatives:
`just_audio_background` (too narrow — no background support for the live
flutter_sound path), a hand-rolled native foreground service (would
reinvent audio_service's lock-screen and Bluetooth/CarPlay integration),
and migrating the live stream onto just_audio (which can't consume a
pushed PCM stream). Known limitation: a live stream interrupted by a call
isn't automatically reconnected — the user must resume manually.
