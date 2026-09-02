# StreamPulse — Flutter client

Two entry points, one codebase:

| Target | Entry point | Audience |
|--------|-------------|----------|
| Mobile app (iOS / Android) | `lib/main.dart` | Listeners, plus broadcaster and admin screens on the go |
| Web console | `lib/main_web.dart` | Broadcasters and admins only |

They share the data, domain and design-system layers; only the navigation
graph differs. The web console deliberately exposes just `/broadcaster` and
`/admin` — listening, playlists, favorites and search stay on mobile.

## Requirements

- Flutter 3.41.x (Dart 3.11.x) — enforced by `environment:` in `pubspec.yaml`

## Running

```sh
flutter pub get
```

Mobile:

```sh
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

Web console (Chrome):

```sh
flutter run -d chrome -t lib/main_web.dart --dart-define=API_BASE_URL=http://localhost:8080
```

`API_BASE_URL` defaults to `http://localhost:8080`. The backend must allow the
console's origin via `CORS_ALLOWED_ORIGINS`.

`GRAFANA_URL` defaults to `http://localhost:3000/d/streampulse` and is used by
the "Open Grafana dashboard" button on the admin screen. Override it for a
deployed Grafana instance:

```sh
flutter run --dart-define=GRAFANA_URL=https://grafana.example.com/d/streampulse
```

## Building

```sh
flutter build apk --release
flutter build web --release -t lib/main_web.dart
./scripts/build_ipa.sh
```

The web build is served as a static site; it uses go_router's default hash
URLs, so no server-side rewrite rule is required.

### iOS AppBundle (.ipa)

`./scripts/build_ipa.sh` (or `make ipa` from the repository root) produces
`build/ios/ipa/StreamPulse-<version>+<build>.ipa`. It needs Xcode, so it
cannot run on Linux — the CI job builds on `macos-latest`.

The script archives with `flutter build ipa --release --no-codesign`, then
assembles the `.ipa` itself. That extra step is not optional: without a
signing certificate the Flutter tool stops at the `.xcarchive` and prints
*"Codesigning disabled with --no-codesign, skipping IPA"*, because
`xcodebuild -exportArchive` refuses to export unsigned. An `.ipa` is a zip
containing `Payload/<App>.app`, which the script builds from the archive's
`.app` and then verifies.

> **The resulting `.ipa` is unsigned.** It is a valid archive deliverable, but
> it will not install on an iPhone and cannot go to TestFlight without being
> re-signed with a distribution certificate. Signing would require an Apple
> Developer account, a `DEVELOPMENT_TEAM` in the Xcode project, and a
> certificate plus provisioning profile held as CI secrets — none of which
> exist in this repository today.

The archive also yields `build/ios/archive/Runner.xcarchive/dSYMs`, uploaded
as a separate CI artifact: without them a release crash report cannot be
symbolicated.

Bundle identifier and application id are `dev.streampulse.app` on both
platforms.

## Checks

```sh
flutter analyze
flutter test
```

## Console access

The console is gated on the signed-in user's role (`domain.Role` in the API):

| Role | Console access |
|------|----------------|
| `user` | None — sent to an "access required" page |
| `broadcaster` | Broadcast |
| `admin` | Broadcast + Users |

## Token storage

`lib/core/storage/` picks a backing store per platform via conditional import:
the OS keychain/keystore on mobile, `localStorage` on web. A browser has no
keychain, so the web build does not use `flutter_secure_storage` — it stores
the short-lived JWT and the revocable refresh token in plain `localStorage`.
