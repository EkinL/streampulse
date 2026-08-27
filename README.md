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
| CI/CD | GitHub Actions |
| Conteneurisation | Docker, Docker Compose |

## Prerequis

- Docker & Docker Compose v2+
- Go 1.26 (dev backend)
- Flutter 3.x (dev mobile)

## Demarrage rapide

```bash
# Lancer toute la stack
make up

# Verifier que l'API fonctionne
curl http://localhost:8080/health
# {"data":{"status":"ok"},"meta":{...}}
```

| Service | URL |
|---------|-----|
| API | http://localhost:8080 |
| Grafana | http://localhost:3000 (admin/admin) |
| Prometheus | http://localhost:9090 |

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

Lecture en arriere-plan et controles ecran verrouille via `audio_service`,
voir [ADR 004](docs/ADR/004-background-audio.md).

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
| `HTTP_READ_TIMEOUT` | 30s | Lecture d'une requete (headers + corps) |
| `HTTP_WRITE_TIMEOUT` | 30s | Ecriture d'une reponse |
| `HTTP_IDLE_TIMEOUT` | 60s | Connexion keep-alive inactive |

Les routes de flux (`/streams/{id}/listen`, `/audio`, `/broadcast`) levent
ces timeouts pour leur propre connexion, voir [ADR 005](docs/ADR/005-http-timeouts.md).

## API

Documentation complete : [docs/api.md](docs/api.md)

Endpoints principaux :
- `POST /auth/register` - Inscription
- `POST /auth/login` - Connexion
- `GET /streams` - Liste des streams
- `GET /streams/:id/listen` - Ecouter un stream (SSE)
- `POST /streams` - Creer un stream (broadcaster)
- `GET/POST/PUT/DELETE /playlists` - CRUD playlists

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
- [ADR 004 - Lecture en arriere-plan et session media](docs/ADR/004-background-audio.md)

## Contribution

1. Creer une branche depuis `develop`
2. Commits conventionnels (`feat:`, `fix:`, `docs:`)
3. Ouvrir une PR vers `develop`
4. Review + CI verte requise

## Licence

MIT
