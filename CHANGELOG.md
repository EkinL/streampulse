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
- Arret automatique des directs sans diffuseur : quand le `POST /broadcast`
  se termine sans etre remplace dans `BROADCAST_GRACE_PERIOD` (10 s), le
  flux est arrete comme par `POST /stop` et les auditeurs deconnectes ; au
  demarrage du serveur, tout flux encore `live` est passe en `ended`. Fin
  des lives fantomes muets apres une app tuee ou un redemarrage
- Connexion sociale Google et Apple : `POST /auth/oauth` verifie l'ID token
  du fournisseur (JWKS, emetteur, audience) et ouvre la meme session que le
  login classique ; boutons cables sur l'ecran de connexion mobile
  (`google_sign_in`, `sign_in_with_apple`). Fournisseurs actives par
  `GOOGLE_OAUTH_CLIENT_IDS` / `APPLE_OAUTH_CLIENT_IDS`, guide dans
  `docs/social-login.md`
- Canal de retour utilisateur (Ce3.4.3) : `POST /feedback` permet a tout compte
  authentifie de signaler un bug ou une suggestion ; `GET /admin/feedback`
  (filtrable par statut) et `PUT /admin/feedback/{id}/status` permettent a
  l'equipe de le consulter et de le faire avancer (`new` → `in_progress` →
  `resolved`), reserve au role `admin`. Cote mobile : ecran **Signaler un
  probleme**, accessible depuis Mon compte, qui joint la version de l'app
  (`package_info_plus`) et la plateforme au signalement. Cote console admin :
  la page **Administration** separe desormais **Utilisateurs** et
  **Signalements** en deux onglets, le second listant les signalements
  (filtrables par statut) avec changement de statut directement depuis la
  liste
- Reverse proxy de production dans la stack : `docker-compose.prod.yml` +
  `caddy/Caddyfile` (`make up-prod`). Caddy termine TLS (Let's Encrypt),
  l'API n'est plus publiee, PostgreSQL et le collecteur OTEL non plus,
  Prometheus et Grafana ne repondent que sur l'interface locale, et
  `TRUSTED_PROXIES` designe le reseau Docker pour que le rate limiting voie
  l'adresse du client
- `APP_ENV=production` refuse de demarrer avec `CORS_ALLOWED_ORIGINS=*` ou
  vide : les origines de la console web doivent etre nommees. Avec le joker,
  `Access-Control-Allow-Credentials` n'est plus annonce (observation O-3 du
  plan de tests)
- Droits RGPD (Ce3.1.4) : `GET /users/me` renvoie toutes les donnees du
  compte, `DELETE /users/me` l'efface avec tout ce qui s'y rattache (cascade
  en base), `DELETE /admin/users/{id}` pour une demande traitee par un
  administrateur ; bouton **Delete my account** dans le profil mobile
- Politique de retention : purge automatique des refresh tokens expires
  (`REFRESH_TOKEN_PURGE_INTERVAL`, 1 h)
- HTTPS natif optionnel (`TLS_CERT_FILE` / `TLS_KEY_FILE`, TLS 1.2 minimum)
  et guide de terminaison TLS par reverse proxy dans `docs/deployment.md`
- `docs/rgpd.md` (registre des traitements, retention, droits, mesures de
  securite, FR + resume EN) et ADR 007 (effacement physique en cascade)
- `PUBLIC_BASE_URL` : URL publique des fichiers uploades, deduite du port et
  de TLS par defaut au lieu d'un `http://localhost` en dur
- Description OpenAPI 3.1 de l'API, servie sur `/openapi.yaml` et rendue sur
  `/docs`, avec un test qui echoue si le routeur et la description divergent
- AppBundle iOS (`.ipa`) produit par la CI, et `make ipa` en local
- Console web pour les roles diffuseur et administrateur
- Seuil de couverture mobile en CI (15 %, `mobile/scripts/coverage_check.sh`,
  `make test-mobile-cover`) ; le chiffre est ecrit dans le resume du job
  GitHub Actions et le rapport `lcov.info` est publie en artefact de PR
- File d'attente de playlist persistee cote serveur : `PUT /playlists/{id}/tracks`
- Preuve de charge du Hub de fan-out : benchmarks et tests a 1000 auditeurs
- Documentation de scalabilite chiffree, ADR 004 a 006, cahier de recette, SLO
  et guide utilisateur
- Plan de tests iteratifs (`docs/plan-de-tests.md`) : niveaux, cartographie
  des cas d'usage, campagne de securite OWASP API, iterations
- Tests d'integration contre PostgreSQL reel (repositories, schema isole par
  paquet) et suite API de bout en bout par role (`internal/integration`)
- Tests de securite : jetons forges, injection SQL, mass assignment, matrice
  RBAC, rate limiting, secrets haches
- Tests unitaires JWT, middlewares (auth, RBAC, rate-limit, CORS), services
  user et music ; `make test-unit`, `make test-integration`, `make cover-check`
- Seuil de couverture en CI (70 %, cible 80 %) et mesure inter-paquets
- `make cover-check` force `-count=1` : un paquet servi par le cache de
  test ne reemet pas sa couverture `-coverpkg`, et le total local
  s'effondrait de 7 points sans qu'aucun test n'ait change
- Chaine de publication (`.github/workflows/release.yml`) : sur un tag `v*`,
  verification de coherence des versions, image multi-architecture publiee sur
  GHCR, APK, `.ipa`, console web, et release GitHub dont les notes sont
  extraites de ce fichier
- Notification automatique : un echec de CI sur une branche partagee, ou un
  scan de securite planifie en echec, ouvre une issue
- Badges de statut CI dans le README, et `docs/operations.md` (cycle de
  livraison, publication, boucle surveillance -> feuille de route)

### Modifie
- Identifiant d'application : `com.example.streampulse` -> `dev.streampulse.app`
  sur iOS et Android
- Seeds de developpement : comptes fictifs `@streampulse.io` uniquement, plus
  aucune adresse personnelle dans le depot

### Securite
- Dependances montees pour corriger **29 vulnerabilites HIGH/CRITICAL**
  detectees par Trivy et govulncheck : `pgx` 5.5.5 -> 5.9.2 (CRITICAL),
  `grpc` 1.62.1 -> 1.82.1 (CRITICAL), `chi` 5.0.12 -> 5.3.0,
  `golang-jwt` 5.2.1 -> 5.3.0, `x/crypto` 0.21.0 -> 0.53.0,
  `x/net` 0.22.0 -> 0.56.0, `x/text` 0.14.0 -> 0.39.0,
  OpenTelemetry 1.24.0 -> 1.44.0
- `x/crypto` 0.53.0 -> 0.55.0 pour corriger **CVE-2026-56854 (CRITICAL)** :
  contournement d'authentification SSH par restriction d'adresse source non
  appliquee (`golang.org/x/crypto/ssh`). Detectee par le scan Trivy de la PR
- Image de base `alpine` 3.19 -> 3.22, avec `apk upgrade` au build : sans lui
  l'image embarque les paquets figes a la date de publication de l'etiquette
- Le conteneur ne tourne plus en **root** : compte de service `streampulse`
  (uid 10001), `WORKDIR /app`, et `/app/uploads` cree et attribue a ce compte
- Scans automatises : `govulncheck` (code Go), Trivy (image et systeme de
  fichiers), Dependabot hebdomadaire. Executes aussi le lundi par
  `schedule`, une CVE publiee apres un merge etant invisible d'un scan de PR

### Corrige
- Chat de live « indisponible » des que la session avait plus de 15 min :
  la poignee de main WebSocket partait avec l'access token brut du stockage,
  expire, et l'API repondait 401 sans que l'app ne renouvelle ni ne retente
  (les appels REST, eux, passent par l'intercepteur Dio). Le token est
  desormais renouvele si besoin avant de se connecter, par un
  `SessionRefresher` partage avec l'intercepteur (un seul renouvellement a la
  fois : le serveur revoque l'ancien refresh token, deux renouvellements
  concurrents deconnectaient l'utilisateur), et le chat se reconnecte seul
  apres une coupure (reseau, app revenue de l'arriere-plan, serveur
  redemarre) avec un delai croissant de 2 a 30 s ; seule la fermeture `1001`
  (fin du live) est definitive
- Direct muet pour les auditeurs : la capture micro du diffuseur vivait dans
  l'ecran de la console, quitter cet ecran (retour a la liste, detail d'un
  flux) ou relancer l'app la coupait alors que le flux restait `live` cote
  serveur. La capture vit desormais dans un provider (`broadcastProvider`),
  survit a la navigation, est relancee par **Gerer** sur un flux live sans
  micro, et rouvre l'envoi vers le backend apres une coupure de connexion
- `/metrics` restreint au role `admin` ; Prometheus scrute un listener interne
- CI mobile reparee : le test de fumee compilait sur une classe inexistante
- Rate limiting inoperant (A-01) : la cle etait `IP:port`, donc un compteur
  neuf par connexion ; elle est desormais l'hote seul
- `X-Forwarded-For` n'etait cru par personne mais lu par tout le monde : il
  est desormais ignore sauf si la connexion vient d'un proxy declare dans
  `TRUSTED_PROXIES`. Sans cette condition, n'importe quel client obtenait un
  compteur vierge en changeant l'en-tete, ou faisait limiter un tiers en
  usurpant son adresse. Dans une chaine de proxies, l'en-tete est parcouru de
  droite a gauche jusqu'a la premiere adresse non declaree
- `chimiddleware.RealIP` retire : il reecrit `r.RemoteAddr` a partir des
  en-tetes de transmission sans verifier leur provenance. chi l'a deprecie
  pour cette raison (GHSA-3fxj-6jh8-hvhx)
- `POST /streams/{id}/start|stop`, `POST /playlists/{id}/tracks` et
  `PUT /admin/users/{id}/role` repondaient 500 sur un identifiant inconnu :
  404 `NOT_FOUND`, documente dans l'OpenAPI

### Connu
- `HEAD /health` renvoie 405 : voir A-02 du
  [cahier de recette](docs/cahier-de-recette.md)
- `http_requests_total` et `http_request_duration_seconds` ne sont jamais
  alimentes : voir O-1 du [plan de tests](docs/plan-de-tests.md)

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

---

## Summary (English)

Follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[SemVer](https://semver.org/). One version number covers all three
deliverables together — the Go API, the Flutter mobile app, and the web
console — since they ship from a single repository and share one REST
contract; a breaking change to that contract forces a major version bump,
because an already-installed mobile client cannot be force-updated.

Highlights across versions: **0.1.0** laid down the Clean Architecture
skeleton, auth, admin, and the mobile music/playlist/player scaffolding;
**0.2.0** upgraded to Go 1.26 and fixed live-playback audio session
interleaving on iOS; **0.3.0** added the web console and server-side
playlist queueing; **1.0.0** is the first end-to-end-complete release —
authentication, role hierarchy, real-time broadcasting via the fan-out
Hub, music catalogue, playlists, favorites, admin, and full observability.
The unreleased changes on top of it add a production reverse-proxy
(Caddy, automatic TLS), hardened production config (no wildcard CORS),
GDPR account rights (access, self-erasure, admin-erasure, automatic
refresh-token purge), native optional HTTPS, the full documentation set
referenced from this repository, and a security pass that patched 29
HIGH/CRITICAL dependency vulnerabilities, moved the container off root,
and fixed the rate-limiter key bug recorded as finding A-01 in the
[acceptance cahier](docs/cahier-de-recette.md). **No git tag exists yet**
in this repository; publishing `v1.0.0` is the pending step described
above.
