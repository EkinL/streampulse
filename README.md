# StreamPulse

[![Backend CI](https://github.com/EkinL/streampulse/actions/workflows/backend.yml/badge.svg?branch=develop)](https://github.com/EkinL/streampulse/actions/workflows/backend.yml)
[![Mobile CI](https://github.com/EkinL/streampulse/actions/workflows/mobile.yml/badge.svg?branch=develop)](https://github.com/EkinL/streampulse/actions/workflows/mobile.yml)
[![Security](https://github.com/EkinL/streampulse/actions/workflows/security.yml/badge.svg?branch=develop)](https://github.com/EkinL/streampulse/actions/workflows/security.yml)

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

Lecture en arriere-plan et controles ecran verrouille via `audio_service`,
voir [ADR 004](docs/ADR/004-background-audio.md).

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
| `APP_ENV` | development | `production` durcit la configuration : le joker CORS est refuse au demarrage |
| `PORT` | 8080 | Port du serveur |
| `DATABASE_URL` | - | URL PostgreSQL |
| `JWT_SECRET` | - | Secret JWT (changer en prod) |
| `JWT_EXPIRY` | 15m | Duree access token |
| `JWT_REFRESH_EXPIRY` | 168h | Duree refresh token |
| `OTEL_ENDPOINT` | localhost:4317 | Endpoint OTEL Collector |
| `LOG_LEVEL` | info | Niveau de log |
| `LOG_FORMAT` | json | Format de log : `json` (indexable) ou `console` (lisible en dev). Une valeur inconnue fait echouer le demarrage |
| `CORS_ALLOWED_ORIGINS` | * | Origines CORS, separees par des virgules. `*` n'est accepte qu'en dehors de `APP_ENV=production` ; avec le joker, `Allow-Credentials` n'est pas annonce |
| `RATE_LIMIT_RPS` | 10 | Requetes/seconde par IP |
| `TRUSTED_PROXIES` | (vide) | Reverse-proxies dont `X-Forwarded-For` est accepte, en CIDR ou adresse. Vide = aucun en-tete de transmission n'est cru |
| `HTTP_READ_TIMEOUT` | 30s | Lecture d'une requete (headers + corps) |
| `HTTP_WRITE_TIMEOUT` | 30s | Ecriture d'une reponse |
| `HTTP_IDLE_TIMEOUT` | 60s | Connexion keep-alive inactive |
| `TLS_CERT_FILE` / `TLS_KEY_FILE` | - | Renseignes ensemble, le serveur sert en HTTPS (TLS 1.2 min.) ; vides, il reste en clair derriere un reverse proxy, voir [deployment.md](docs/deployment.md#https) |
| `PUBLIC_BASE_URL` | déduit | URL publique de l'API pour les liens des fichiers uploades ; vide = `http(s)://localhost:PORT` selon TLS |
| `REFRESH_TOKEN_PURGE_INTERVAL` | 1h | Purge des refresh tokens expires (retention, voir [rgpd.md](docs/rgpd.md)) |

Les routes de flux (`/streams/{id}/listen`, `/audio`, `/broadcast`) levent
ces timeouts pour leur propre connexion, voir [ADR 005](docs/ADR/005-http-timeouts.md).

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
- `GET/DELETE /users/me` - Consulter et supprimer son propre compte (RGPD)

## Roles

| Role | Permissions |
|------|-------------|
| user | Ecouter, playlists, favoris, consulter et supprimer son compte |
| broadcaster | + creer/gerer des streams |
| admin | + gestion des utilisateurs (roles, suppression) |

## Tests

```bash
# Backend, suite unitaire (sans base)
cd backend && make test-unit
cd backend && make load-test   # 1000 auditeurs sur le Hub + 500 clients SSE reels
cd backend && make bench       # cout d'un chunk pour 10 a 10 000 auditeurs

# Backend, suite d'integration : repositories et API bout en bout contre PostgreSQL
export DATABASE_URL=postgres://localhost:5432/streampulse_test?sslmode=disable
make test-integration

# Tout, avec le seuil de couverture de la CI
make cover-check

# Mobile, avec le seuil de couverture de la CI
make test-mobile-cover
```

Ce qui est teste, a quel niveau et dans quel ordre : [docs/plan-de-tests.md](docs/plan-de-tests.md).

## Documentation

| Document | Pour quoi |
|----------|-----------|
| [docs/api.md](docs/api.md) + `/docs` | Le contrat REST, decrit en OpenAPI 3.1 |
| [docs/user-stories.md](docs/user-stories.md) | Fonctionnalites sous forme de user stories, tracees vers les cas d'usage et les tests |
| [docs/diagrammes.md](docs/diagrammes.md) | Diagrammes UML et BPMN (cas d'usage, classes, sequences, etats, processus, composants) |
| [docs/base-de-donnees.md](docs/base-de-donnees.md) | Modele conceptuel (MCD), modele physique et dictionnaire de donnees |
| [docs/securite.md](docs/securite.md) | Schema general de securite : zones de confiance, defense en profondeur, RBAC, OWASP Top 10 |
| [docs/guide-utilisateur.md](docs/guide-utilisateur.md) | Prise en main par role et plan de formation |
| [docs/accessibilite.md](docs/accessibilite.md) | Utilisation en situation de handicap : lecteur d'ecran, taille du texte, contraste, limites connues |
| [docs/accessible/](docs/accessible/streampulse-documentation.epub) | La documentation technique complete en EPUB, plus le guide utilisateur et l'accessibilite en audio (`make docs-accessible`) |
| [docs/performance.md](docs/performance.md) | Fluidite de l'interface mesuree au profileur Flutter (DevTools / VM timeline), pas a l'oeil |
| [docs/plan-de-tests.md](docs/plan-de-tests.md) | Plan de tests iteratifs : unitaires, integration, securite, cartographie des cas d'usage |
| [docs/cahier-de-recette.md](docs/cahier-de-recette.md) | 58 cas de recette executes |
| [docs/slo.md](docs/slo.md) | Objectifs de niveau de service et politique de budget d'erreur |
| [docs/rgpd.md](docs/rgpd.md) | Donnees personnelles : registre, retention, droits (acces, effacement), mesures de securite |
| [docs/deployment.md](docs/deployment.md) | Deploiement |
| [CHANGELOG.md](CHANGELOG.md) | Historique des versions |
| [docs/operations.md](docs/operations.md) | Cycle de livraison, publication d'une version, boucle surveillance -> feuille de route |

## Decisions architecturales

- [ADR 001 - Clean Architecture](docs/ADR/001-clean-architecture.md)
- [ADR 002 - Riverpod](docs/ADR/002-state-management-riverpod.md)
- [ADR 003 - SSE Streaming](docs/ADR/003-streaming-sse.md)
- [ADR 004 - Lecture en arriere-plan et session media](docs/ADR/004-background-audio.md)
- [ADR 004 - Observabilite : OTEL, Prometheus, logs correles](docs/ADR/004-observabilite-otel.md)
- [ADR 005 - PostgreSQL et pgx sans ORM](docs/ADR/005-choix-postgresql.md)
- [ADR 006 - JWT court et refresh token opaque](docs/ADR/006-strategie-auth-jwt.md)
- [ADR 007 - Effacement physique en cascade (RGPD)](docs/ADR/007-effacement-compte-rgpd.md)
- [ADR 008 - Dashboard Grafana, traces distribuees et alertes](docs/ADR/008-dashboard-alertes-grafana.md)

## Scalabilite

[docs/scalability.md](docs/scalability.md) chiffre ce que la plateforme
encaisse et ou se situe le mur, a partir de mesures reproductibles
(`make bench`, `make load-test`).

En resume, a 100 flux simultanes et 50 auditeurs par flux : **le reseau sature
en premier** (856 Mbit/s en SSE, soit 86 % d'une carte 1 Gbit/s) alors que le
serveur tourne a 20 % de sa capacite. Le facteur limitant est la bande
passante sortante, pas le code.

## Fluidite de l'interface

[docs/performance.md](docs/performance.md) mesure la fluidite de l'app mobile
avec le profileur Flutter (timeline du VM Service, la meme source que
Flutter DevTools), pas a l'oeil. En resume : le scroll d'une liste de 66
elements tient le budget de 16,67 ms (60 Hz) sur 99,3 % des images en mode
debug (0 image en jank severe) ; le point chaud identifie n'est pas le scroll
mais le rafraichissement periodique de la liste, qui reconstruit tout au lieu
de ne mettre a jour que ce qui a change.

## Contribution

1. Creer une branche depuis `develop`
2. Commits conventionnels (`feat:`, `fix:`, `docs:`)
3. Ouvrir une PR vers `develop`
4. Review + CI verte requise

## Licence

MIT
