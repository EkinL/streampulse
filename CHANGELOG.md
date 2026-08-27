# Changelog

Toutes les evolutions notables de StreamPulse sont consignees ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le
versionnage suit [SemVer](https://semver.org/lang/fr/).

## Portee du versionnage

Un numero de version couvre **les trois livrables ensemble** : l'API Go, l'app
mobile Flutter et la console web. Ils sont publies depuis un depot unique et
partagent le meme contrat REST, decrit par
[`backend/api/openapi.yaml`](backend/api/openapi.yaml).

La version fait donc foi pour :

| Livrable | Ou la lire |
|----------|------------|
| API | `info.version` de la description OpenAPI, servie sur `/openapi.yaml` |
| Mobile | `version:` de `mobile/pubspec.yaml`, embarque dans l'APK et le `.ipa` |
| Console web | meme source que le mobile, meme build |

Une evolution **incompatible du contrat REST** impose une version majeure : un
client mobile deja installe ne peut pas etre mis a jour de force.

## [Non publie]

### Ajoute
- Description OpenAPI 3.1 de l'API, servie sur `/openapi.yaml` et rendue sur
  `/docs`, avec un test qui echoue si le routeur et la description divergent
- AppBundle iOS (`.ipa`) produit par la CI, et `make ipa` en local
- Console web pour les roles diffuseur et administrateur
- File d'attente de playlist persistee cote serveur : `PUT /playlists/{id}/tracks`
- Preuve de charge du Hub de fan-out : benchmarks et tests a 1000 auditeurs
- Documentation de scalabilite chiffree, ADR 004 a 006, cahier de recette, SLO
  et guide utilisateur

### Modifie
- Identifiant d'application : `com.example.streampulse` -> `dev.streampulse.app`
  sur iOS et Android

### Corrige
- `/metrics` restreint au role `admin` ; Prometheus scrute un listener interne
- CI mobile reparee : le test de fumee compilait sur une classe inexistante

### Connu
- Le rate limiting est inoperant : voir A-01 du
  [cahier de recette](docs/cahier-de-recette.md)
- `HEAD /health` renvoie 405 : voir A-02

## [1.0.0] — 2026-08-27

Premiere version complete : les trois livrables fonctionnent de bout en bout.

### Ajoute
- **Authentification** : inscription, connexion, rotation de jeton. JWT HS256
  de 15 minutes, refresh token opaque a usage unique, mots de passe en bcrypt
- **Roles** : `anonymous` < `user` < `broadcaster` < `admin`, hierarchiques
- **Diffusion temps reel** : Hub de fan-out en goroutines et channels,
  `GET /streams/{id}/listen` en SSE et `GET /streams/{id}/audio` en flux brut,
  ingestion par `POST /streams/{id}/broadcast`
- **Catalogue musical** : upload de fichier ou ajout par URL, recherche plein
  texte PostgreSQL, recherche globale sur `/search`
- **Playlists** : CRUD complet et gestion de la file d'attente
- **Favoris** : sur les flux et sur les morceaux
- **Administration** : liste des comptes et changement de role
- **Observabilite** : traces OpenTelemetry, metriques Prometheus, dashboard
  Grafana, logs structures
- **Mobile Flutter** : lecteur audio avec progression, ecoute du direct,
  interface diffuseur, design system sombre
- **CI/CD** : deux workflows GitHub Actions — lint, tests, build APK, build web,
  build iOS, image Docker sur tag

### Securite
- Requetes SQL parametrees via `pgx` : aucune concatenation d'entree
  utilisateur ([ADR 005](docs/ADR/005-choix-postgresql.md))
- Refresh tokens stockes haches en SHA-256
- Image Docker multi-stage `golang:1.26-alpine` vers `alpine:3.19`

## [0.3.0] — 2026-08-26

### Ajoute
- Console web pour diffuseurs et administrateurs, cible `lib/main_web.dart`
- Stockage de jeton par plateforme : keychain sur mobile, `localStorage` sur web
- File d'attente de playlist : colonne `position` et reordonnancement
  transactionnel

### Corrige
- CI mobile verte : Flutter 3.41.6, `flutter analyze` sans avertissement
- Cible de deploiement iOS portee a 15.0

## [0.2.0] — 2026-08-25

### Modifie
- Go 1.22 -> **1.26** : `go.mod`, Dockerfile, CI, et tout ce que la montee de
  version a revele

### Corrige
- 12 signalements `errcheck` et `staticcheck`, dont le nettoyage des uploads
  echoues
- Lecture du direct sur mobile : entrelacement du sink et session audio iOS

### Ajoute
- Tests : filestore, chargement de `.env`, detection de cle dupliquee
- `make mobile-run`, avec `dart_define.json` genere depuis l'adresse LAN

## [0.1.0] — 2026-05-04

### Ajoute
- Squelette Clean Architecture du backend Go : domaine, application,
  infrastructure, transport
- Authentification, administration, socle d'infrastructure
- Bibliotheque musicale, playlists, lecteur, recherche, design system mobile
- Echafaudages de plateforme iOS et Android

---

## Comment publier une version

```bash
# 1. Basculer [Non publie] vers la nouvelle version dans ce fichier
# 2. Aligner mobile/pubspec.yaml et info.version de openapi.yaml
# 3. Taguer : le job docker de la CI se declenche sur les tags
git tag -a v1.1.0 -m "v1.1.0"
git push origin v1.1.0
```

**Aucun tag n'existe encore dans le depot.** `v1.0.0` ci-dessus decrit l'etat
actuel de `develop` et doit etre pose pour que le job `docker` de
`.github/workflows/backend.yml`, declenche par `startsWith(github.ref, 'refs/tags/')`,
s'execute pour la premiere fois.
