# StreamPulse

Plateforme de streaming audio en temps reel avec backend Go et application mobile Flutter.

## Architecture

```
                    ┌─────────────┐
                    │  Flutter App │
                    │  (iOS/Android)│
                    └──────┬──────┘
                           │ HTTP/SSE
                    ┌──────▼──────┐
                    │   Go API    │
                    │  (chi router)│
                    └──────┬──────┘
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼─────┐ ┌───▼───┐ ┌─────▼─────┐
        │ PostgreSQL │ │  Hub  │ │   OTEL    │
        │    (DB)    │ │(fan-out)│ │ Collector │
        └───────────┘ └───────┘ └─────┬─────┘
                                       │
                              ┌────────▼────────┐
                              │ Prometheus/Grafana│
                              └─────────────────┘
```

### Backend (Clean Architecture)

```
domain/          Entites, interfaces (zero import externe)
application/     Use cases, services metier
infrastructure/  PostgreSQL, JWT, OTEL, Streaming Hub
transport/       Handlers HTTP, middlewares, DTOs
```

### Mobile (Feature-first)

```
core/            Network (Dio), Storage, Utils
features/        auth, streams, playlists, favorites, admin
shared/          Widgets reutilisables
app/             Router, Theme, Constants
```

## Stack technique

| Composant | Technologie |
|-----------|-------------|
| Backend | Go 1.26, chi, pgx, zerolog |
| Base de donnees | PostgreSQL 16 |
| Auth | JWT HS256 (bcrypt) |
| Streaming | SSE (fan-out Hub) |
| Mobile | Flutter 3.x, Riverpod, Dio |
| Observabilite | OpenTelemetry, Prometheus, Grafana |
| Contrat API | OpenAPI 3.1 (Redocly lint) |
| CI/CD | GitHub Actions |
| Conteneurisation | Docker, Docker Compose |

## Prerequis

- Docker & Docker Compose v2+
- Go 1.26 (dev backend)
- Flutter 3.x (dev mobile)

## Demarrage rapide

```bash
# Secrets locaux (webhook Discord des alertes Grafana) - voir .env.example
cp .env.example .env
# puis remplir DISCORD_WEBHOOK_URL

# Lancer toute la stack
make up

# Verifier que l'API fonctionne
curl http://localhost:8080/health
# {"data":{"status":"ok"},"meta":{...}}
```

Sans ce `.env`, la stack demarre quand meme mais les alertes Grafana n'ont nulle part ou notifier (webhook vide, echec silencieux).

| Service | URL |
|---------|-----|
| API | http://localhost:8080 |
| Grafana | http://localhost:3000 (admin/admin) |
| Prometheus | http://localhost:9090 |
| Tempo (traces) | http://localhost:3200 |

## Developpement

### Backend
```bash
cd backend
cp .env.example .env
make run      # Lancer le serveur
make test     # Lancer les tests
make lint     # Linter
```

### Mobile
```bash
cd mobile
flutter pub get
flutter run
```

## Livrables

| Livrable | Commande | Sortie |
|----------|----------|--------|
| Binaire API | `cd backend && make build` | `backend/bin/server` |
| Image Docker API | `cd backend && make docker-build` | `streampulse-api` |
| APK Android | `cd mobile && flutter build apk --release` | `mobile/build/app/outputs/flutter-apk/` |
| **AppBundle iOS (.ipa)** | `make ipa` | `mobile/build/ios/ipa/StreamPulse-<version>+<build>.ipa` |
| Console web | `cd mobile && flutter build web --release -t lib/main_web.dart` | `mobile/build/web/` |

`make build-all` enchaine binaire API + APK + `.ipa`.

Le `.ipa` **n'est pas signe** : c'est un livrable d'archive valide, mais il
doit etre re-signe avec un certificat de distribution pour s'installer sur un
appareil ou partir en TestFlight. Details : [mobile/README.md](mobile/README.md#ios-appbundle-ipa).
Xcode est requis, donc le job CI correspondant tourne sur `macos-latest`.

Identifiant d'application : `dev.streampulse.app` (iOS et Android).

## Variables d'environnement

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 8080 | Port du serveur |
| `DATABASE_URL` | - | URL PostgreSQL |
| `JWT_SECRET` | - | Secret JWT (changer en prod) |
| `JWT_EXPIRY` | 15m | Duree access token |
| `JWT_REFRESH_EXPIRY` | 168h | Duree refresh token |
| `OTEL_ENDPOINT` | localhost:4317 | Endpoint OTEL Collector |
| `LOG_LEVEL` | info | Niveau de log |
| `CORS_ALLOWED_ORIGINS` | * | Origines CORS |
| `RATE_LIMIT_RPS` | 10 | Requetes/seconde par IP |

## API

Le contrat REST est decrit en **OpenAPI 3.1** : [backend/api/openapi.yaml](backend/api/openapi.yaml).
C'est la source de verite unique — un test Go casse le build si le routeur et
la description divergent.

| Ou | Quoi |
|----|------|
| [backend/api/openapi.yaml](backend/api/openapi.yaml) | La description, dans le depot |
| http://localhost:8080/openapi.yaml | La meme, embarquee dans le binaire qui tourne |
| http://localhost:8080/docs | Swagger UI |
| [docs/api.md](docs/api.md) | Guide narratif : conventions, flux d'auth, quickstart |

```bash
# Valider la description
cd backend && make openapi-lint

# Verifier qu'elle correspond aux routes reellement servies
cd backend && go test ./internal/transport/http/
```

Endpoints principaux :
- `POST /auth/register` - Inscription
- `POST /auth/login` - Connexion
- `GET /streams` - Liste des streams
- `GET /streams/:id/listen` - Ecouter un stream (SSE)
- `GET /streams/:id/audio` - Ecouter un stream (flux audio brut)
- `POST /streams` - Creer un stream (broadcaster)
- `GET/POST/PUT/DELETE /playlists` - CRUD playlists + file d'attente
- `GET /search` - Recherche globale streams + musiques

## Roles

| Role | Permissions |
|------|-------------|
| user | Ecouter, playlists, favoris |
| broadcaster | + creer/gerer des streams |
| admin | + gestion des utilisateurs |

## Tests

```bash
# Backend
cd backend && go test -race ./...

# Mobile
cd mobile && flutter test
```

## Decisions architecturales

- [ADR 001 - Clean Architecture](docs/ADR/001-clean-architecture.md)
- [ADR 002 - Riverpod](docs/ADR/002-state-management-riverpod.md)
- [ADR 003 - SSE Streaming](docs/ADR/003-streaming-sse.md)
- [ADR 004 - Observabilite](docs/ADR/004-observabilite.md)

## Contribution

1. Creer une branche depuis `develop`
2. Commits conventionnels (`feat:`, `fix:`, `docs:`)
3. Ouvrir une PR vers `develop`
4. Review + CI verte requise

## Licence

MIT
