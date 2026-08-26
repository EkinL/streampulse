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

## Building

```sh
flutter build apk --release
flutter build web --release -t lib/main_web.dart
```

The web build is served as a static site; it uses go_router's default hash
URLs, so no server-side rewrite rule is required.

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
