# Plan de tests iteratifs

Ce document est le plan de tests de StreamPulse : ce qui est teste, a quel
niveau, avec quels outils, dans quel ordre, et comment on decide qu'une
iteration est terminee. Il repond au critere Ce3.2.1 du bloc 3 (RNCP 38822) :
*plan de tests iteratifs — unitaires, integration, securite — couvrant tous
les cas d'usage*, et a l'exigence du sujet d'un code testable unitairement a
80 % minimum.

Il complete le [cahier de recette](cahier-de-recette.md), qui consigne les
resultats observes d'une campagne manuelle. Ici, tout ce qui est decrit est
automatise et rejouable par `make`.

## 1. Objectifs et regles

| Objectif | Mesure | Etat au 2026-09-01 |
|----------|--------|--------------------|
| Chaque cas d'usage du sujet a au moins un test automatise a chaque niveau applicable | cartographie de la section 3 | 19/19 cas couverts |
| Couverture de code du module Go | `make cover-check` | **91,1 %** (94,1 % hors `cmd/server`) — cible 80 % atteinte, seuil CI releve a 80 % |
| Couverture de lignes de l'app Flutter | `make test-mobile-cover` | **80,4 %** (455 tests) — cible 80 % atteinte, seuil CI releve a 80 % (iteration 3) |
| Aucun test rouge sur `develop` | CI `backend.yml` / `mobile.yml` | vert |
| Tout defaut trouve donne d'abord un test rouge, puis un correctif | section 6 | 4 defauts, 4 corriges |

Regles appliquees a chaque PR :

- **Le test est ecrit avec le code, pas apres.** Une PR qui ajoute un
  comportement ajoute le test qui le decrit ; la CI echoue sous le seuil de
  couverture (`COVERAGE_MIN` : 80 % backend et mobile). Le chiffre de chaque
  run est ecrit dans le resume du job GitHub Actions et le rapport
  (`coverage.out`, `lcov.info`) est publie en artefact de PR : la trajectoire
  se lit d'une PR a l'autre.
- **Un defaut commence par un test rouge.** Les quatre anomalies de la
  section 6 ont chacune un test qui echouait avant le correctif.
- **Les cas de refus comptent autant que les cas nominaux.** Chaque endpoint
  est teste avec un anonyme, un role insuffisant, un non-proprietaire, un
  identifiant inconnu et un identifiant invalide.
- **Ce qu'un mock ne peut pas prouver est teste contre le vrai composant.**
  Contraintes d'unicite, cascades, transactions, recherche plein texte :
  PostgreSQL reel. Fan-out SSE : Hub reel, vrais clients HTTP.
- **`-race` partout**, jamais de `sleep` fixe : les attentes passent par
  `waitFor` avec un delai maximal.

## 2. Niveaux de test

| Niveau | Ce qu'il prouve | Reel / simule | Ou | Commande |
|--------|-----------------|---------------|----|----------|
| **Unitaire Go** | Regles metier et validation des services, hierarchie des roles, emission et validation des JWT, comportement de chaque middleware, chargement de la configuration, ecriture des fichiers | Repositories remplaces par les mocks de `backend/testutil` | `internal/application`, `internal/domain`, `internal/infrastructure/{auth,config,filestore,observability}`, `internal/transport/http/middleware` | `make test-unit` |
| **Contrat** | La description OpenAPI et le routeur ne divergent pas ; toute operation documentee `bearerAuth` repond 401 sans jeton ; `/metrics` est reserve a l'admin ; l'identifiant de correlation traverse toute la chaine | Routeur reel, services absents (les requetes s'arretent aux middlewares) | `internal/transport/http/*_test.go` | `make test-unit` |
| **Integration base** | Unicite de l'email, `ON DELETE CASCADE`, expiration des refresh tokens evaluee en base, recherche plein texte (stemming, casse), compactage des positions, **rollback du reordonnancement** de playlist, idempotence des migrations | PostgreSQL reel, schema dedie `it_postgres` | `internal/infrastructure/postgres/repos_integration_test.go` | `make test-integration` |
| **Integration API** | Le serveur complet — request id, tracing, CORS, rate-limit, JWT, RBAC, services, repositories, Hub — vu par un client HTTP, scenario par scenario et role par role | Tout est reel sauf l'exporteur OTEL (muet) et le dossier d'upload (temporaire) ; schema dedie `it_api` | `internal/integration/` | `make test-integration` |
| **Securite** | Jetons forges (payload modifie, autre secret, `alg=none`, expire), rejeu de refresh token, injection SQL, mass assignment, matrice role x endpoint, propriete distincte du role, rate limiting, secrets haches, correlation des erreurs | Unitaire et integration | `auth/jwt_test.go`, `middleware/*_test.go`, `integration/security_test.go`, `integration/rbac_test.go` | les deux commandes |
| **Charge** | Le Hub encaisse N auditeurs sans bloquer ni fuir | Hub reel, 1000 clients | branche `test/hub-load-proof` (PR ouverte) | `make bench`, `make load-test` a la fusion |
| **Mobile** | Modeles et repositories (parsing, branches d'erreur HTTP), providers Riverpod (etats, appels reseau simules), intercepteur d'authentification (refresh de jeton, retry, echec), widgets partages et de features, ecrans (listes, details, formulaires, dialogues, navigation), console web (roles admin, destinations, ecran de connexion) | `flutter_test`, `mocktail` pour les repositories/`Dio`, sources natives (stockage, lecteur audio) remplacees par des faux, `HttpOverrides` pour l'intercepteur HTTP | `mobile/test/` | `make test-mobile-cover` |
| **Recette manuelle** | L'API telle qu'un client la consomme, avec les codes et corps reellement observes | Stack `docker compose` | [cahier-de-recette.md](cahier-de-recette.md) | `curl` |

### Isolation des tests d'integration

`go test ./...` execute les paquets en parallele. Pour que deux suites ne se
marchent pas dessus, `testutil.OpenTestDB` donne a chaque paquet **son propre
schema PostgreSQL** (`search_path = it_<paquet>,public`), detruit et recree a
chaque run, migrations appliquees. La base designee par `DATABASE_URL` n'a
donc besoin ni d'etre vide ni d'etre reinitialisee, et une base de
developpement peut servir sans risque pour ses tables `public`.

Sans `DATABASE_URL`, ces tests se declarent ignores : la suite unitaire reste
jouable partout. La CI fournit une base (service `postgres` de
`backend.yml`), les tests d'integration y tournent a chaque PR.

Les comptes de fixture sont crees en base avec un hash bcrypt a cout minimal
puis connectes par l'API : sous `-race`, un bcrypt a cout 12 prend plusieurs
secondes, et la suite passait de 170 s a 28 s. L'inscription reelle, avec son
cout 12, reste testee par `TestAuth_RegisterLoginRefresh` et
`TestAuth_SecretsAreStoredHashed`.

## 3. Cartographie cas d'usage → tests

Les cas d'usage sont ceux du sujet (fonctionnalites 1.x a 4.x). Chaque ligne
donne les tests qui le couvrent a chaque niveau ; `—` signifie que le niveau
ne s'applique pas.

| Ref | Cas d'usage | Unitaire | Integration | Securite | Recette |
|-----|-------------|----------|-------------|----------|---------|
| UC-01 | Inscription (1.1) | `TestAuthService_Register` | `TestAuth_RegisterLoginRefresh`, `TestAuth_RegisterValidation`, `TestUserRepo_DuplicateEmail` | `TestAuth_SecretsAreStoredHashed` (bcrypt 12), champ `role` refuse | R-10 a R-12 |
| UC-02 | Connexion (1.1) | `TestAuthService_Login` | `TestAuth_RegisterLoginRefresh` (mauvais mot de passe, compte inconnu) | injection dans l'email → 401 (`TestSecurity_SQLInjectionIsNeutralised`) | R-13, R-14 |
| UC-03 | Rafraichissement de session (1.1) | `TestAuthService_RefreshToken` | `TestAuth_RegisterLoginRefresh` (rotation, rejeu, revocation par login), `TestRefreshTokenRepo_*` | `TestAuth_ExpiredTokensRejected`, refresh token stocke en SHA-256 | R-15, R-16 |
| UC-04 | Anonyme : consultation limitee (1.2) | — | `TestRBAC_EndpointMatrix` (lignes `all`), `TestStreams_ListPagination` | 401 sur toute route documentee `bearerAuth` (`TestDocumentedAuthMatchesMiddleware`) | R-20 a R-25 |
| UC-05 | User ecoute un flux en direct (1.3, 2.1, 3.1) | `TestStreamService_*` | `TestStreams_LifecycleWithLiveListener` (SSE, `connected`, chunk relaye, compteur d'auditeurs, deconnexion) | ecoute d'un flux non demarre → `STREAM_NOT_LIVE` | R-57 |
| UC-06 | Favoris de flux (1.3) | — | `TestFavorites_Streams`, `TestFavoriteRepo` | flux inconnu → 404, cle etrangere en base | R-38 a R-40 |
| UC-07 | Favoris de morceaux (1.3) | — | `TestFavorites_Music`, `TestMusicFavoriteRepo` | morceau inconnu → 404 | — |
| UC-08 | Playlists : CRUD (2.2) | `TestPlaylistService_*` | `TestPlaylists_QueueManagement`, `TestPlaylistRepo_ListsAndVisibility` | `TestPlaylists_VisibilityAndOwnership` (privee → 404, tiers → 403) | R-30 a R-32, R-37 |
| UC-09 | Playlists : file d'attente (2.2) | `TestPlaylistService_ReorderTracks` | `TestPlaylists_QueueManagement` (positions, liste incomplete, doublon, piste etrangere, compactage), **`TestPlaylistRepo_ReorderIsAtomic`** | `position` dans le corps refuse | R-33 a R-36 |
| UC-10 | Diffuseur : creer, demarrer, diffuser, arreter (1.4, 3.2) | `TestStreamService_*` | `TestStreams_LifecycleWithLiveListener`, `TestStreams_OwnershipAndErrors`, `TestStreamRepo_Lifecycle` | autre diffuseur et admin → 403 ; `status` dans le corps refuse | R-50 a R-56 |
| UC-11 | Diffuseur : sources audio, fichier ou URL (1.4) | `TestMusicService_*` | `TestMusic_CatalogueByURL`, `TestMusic_UploadFile` (multipart, fichier sur disque, rien ecrit en cas de refus), `TestMusicRepo_CRUDAndSearch` | tiers → 403 ; `uploaded_by` refuse | — |
| UC-12 | Admin : gestion des comptes (1.5) | `TestUserService_*` | `TestAdmin_UsersAndRoles` (liste sans hash, pagination, role invalide, inconnu → 404, promotion effective au jeton suivant) | `TestRBAC_EndpointMatrix` (`adminOnly`), `TestRequireRoleMatrix` | R-60 a R-63 |
| UC-13 | Admin : metriques globales (1.5, 4.3) | — | `TestAdmin_MetricsExposePlatformGauges` | `TestMetricsAccess` (anonyme 401, user et broadcaster 403) | R-64 a R-66 |
| UC-14 | Configuration 12-Factor (2.3) | `config_test.go` (defauts, `.env`, format de logs invalide refuse) | — | secret JWT requis au demarrage | — |
| UC-15 | Observabilite : logs JSON, correlation, traces (4.1, 4.2) | `logger_test.go`, `requestid_test.go`, `logging_test.go` | `TestRequestIDIsCorrelatedEndToEnd`, `TestSecurity_EveryResponseIsCorrelated` | les 401/403 portent aussi `X-Request-ID` | R-01 |
| UC-16 | Contrat OpenAPI servi et exact | `docs_handler_test.go` | `TestOpenAPICoversEveryRoute`, `TestOpenAPIOperationIDsAreUnique`, `TestDescriptionRoutesArePublic` | — | R-02, R-03 |
| UC-17 | Mobile : demarrage, session, routes | `widget_test.dart`, `api_endpoints_test.dart`, `secure_storage_test.dart`, `auth_provider_test.dart`, `api_client_interceptors_test.dart` (refresh de jeton, retry, echec) | — | jetons en keychain / `localStorage` (`secure_storage_test.dart`) ; retry unique et purge des jetons sur refresh rejete (`api_client_interceptors_test.dart`) | guide utilisateur |
| UC-18 | Console web diffuseur / admin | `console_*_test.dart` (roles admin, destinations par role, ecran de connexion, shell) | — | destinations filtrees par role | guide utilisateur |
| UC-19 | Lecteur audio mobile (3.1) et interface diffuseur (3.2) | Lecteur : `player_provider_test.dart`, `mini_player_test.dart`, `music_player_screen_test.dart` (file d'attente, volume, ajout a une playlist). Diffuseur : ecran hors perimetre (iteration 4), voir section 5 | — | — | guide utilisateur, recette manuelle sur simulateur |
| UC-20 | Droits RGPD : acces et effacement de son compte (Ce3.1.4) | `TestUserService_DeleteUser`, `TestPurgeExpiredRefreshTokens` | `TestUsers_AccessAndErasure` (profil sans hash, cascade sur 6 tables, refresh et login refuses, email libere), `TestCascadeOnUserDelete` | `TestRBAC_EndpointMatrix` (`/users/me` authentifie) ; jeton encore valide → 404 | R-80 a R-85 |
| UC-21 | Admin : effacement sur demande (Ce3.1.4) | `TestUserService_DeleteUser` | `TestAdmin_DeleteUser` (id invalide, inconnu, disparition de la liste) | `TestRBAC_EndpointMatrix` (`adminOnly`), user → 403 | R-86, R-87 |
| UC-22 | Flux chiffres : HTTPS natif ou reverse proxy (Ce3.1.4) | `config_test.go` (TLS desactive par defaut, actif avec les deux fichiers, refus d'un seul, joker CORS refuse en production) | — | TLS 1.2 minimum ; API non publiee derriere Caddy (`docker-compose.prod.yml`) | R-88 a R-90 |

## 4. Campagne de securite

Les verifications suivent l'OWASP API Security Top 10 (2023). Chaque ligne
est un test automatise qui s'execute a chaque PR.

| Risque | Ce qui est verifie | Tests | Resultat |
|--------|--------------------|-------|----------|
| API1 — autorisation au niveau objet | Un non-proprietaire ne modifie ni flux, ni playlist, ni morceau ; l'admin non plus (propriete ≠ role) ; un jeton d'un autre compte n'ouvre pas mes ressources | `TestStreams_OwnershipAndErrors`, `TestPlaylists_VisibilityAndOwnership`, `TestMusic_CatalogueByURL/propriete`, `TestSecurity_ForgedTokensAreRejected` | OK |
| API2 — authentification | `alg=none`, autre secret, payload modifie (`role` → `admin`), jeton expire, en-tete malforme, refresh rejoue, refresh expire ; mots de passe bcrypt 12, refresh tokens SHA-256 | `jwt_test.go`, `middleware/auth_test.go`, `TestAuth_*`, `TestSecurity_ForgedTokensAreRejected` | OK |
| API3 — autorisation au niveau propriete (mass assignment) | Tout champ hors contrat est refuse : `role` a l'inscription, `owner_id`, `status`, `position`, `id`, `uploaded_by` | `TestSecurity_UnknownFieldsRejected`, `TestAuth_RegisterValidation` | OK |
| API4 — consommation de ressources | Rate limiting par hote, burst puis 429, recharge, `X-Forwarded-For` derriere un proxy | `middleware/ratelimit_test.go` | OK apres correctif A-01 ; taille des corps non bornee → O-2 |
| API5 — autorisation au niveau fonction | Matrice 4 roles x 16 routes ; hierarchie `anonymous < user < broadcaster < admin` ; role inconnu jamais accepte | `TestRBAC_EndpointMatrix`, `TestRequireRoleMatrix`, `TestRequireRoleRejectsUnknownRole`, `TestMetricsAccess` | OK |
| API8 — mauvaise configuration | Seules les origines configurees passent le preflight CORS ; le joker n'annonce pas `Allow-Credentials` ; `APP_ENV=production` refuse `CORS_ALLOWED_ORIGINS=*` ou vide ; `X-Request-ID` expose au navigateur ; TLS natif refuse une configuration a moitie renseignee | `middleware/cors_test.go` (`TestCORSCredentialsOnlyWithNamedOrigins`), `config_test.go` (`TestLoadRejectsWildcardCORSInProduction`, `TestLoadRejectsHalfTLSConfig`) | OK ; O-3 corrigee ; terminaison TLS fournie par `docker-compose.prod.yml` + `caddy/Caddyfile`, voir [deployment.md](deployment.md#https) |
| Donnees personnelles (RGPD) | Une personne lit tout ce qui la concerne et efface son compte ; rien ne subsiste dans les six tables liees ; ses anciens jetons ne donnent plus acces a rien ; les refresh tokens expires sont purges | `TestUsers_AccessAndErasure`, `TestAdmin_DeleteUser`, `TestCascadeOnUserDelete`, `TestPurgeExpiredRefreshTokens` | OK ; registre et retention dans [rgpd.md](rgpd.md) |
| Injection | Charges SQL a l'inscription, a la connexion, dans la recherche, dans un identifiant de chemin : stockees telles quelles ou rejetees, tables intactes | `TestSecurity_SQLInjectionIsNeutralised` | OK (requetes parametrees pgx, ADR 005) |
| Fuite d'information | Mot de passe et hash jamais renvoyes ; playlist privee d'autrui → 404 et non 403 ; erreurs correlables sans detail interne | `TestAuth_RegisterLoginRefresh`, `TestAdmin_UsersAndRoles`, `TestPlaylists_VisibilityAndOwnership`, `TestSecurity_EveryResponseIsCorrelated` | OK ; ecritures sur playlist privee → O-4 |

## 5. Iterations

### Iteration 0 — etat de depart (avant cette campagne)

13 tests de services (`auth`, `stream`, `playlist`), tests de configuration,
de filestore, de logger, d'identifiant de requete, de contrat OpenAPI et
d'acces a `/metrics`. Aucun test contre la base, aucun test de securite
explicite, aucun scenario de bout en bout.

Couverture par paquet : `postgres` 1,5 %, `handlers` 3,4 %, `auth` 0 %,
`streaming` 0 %, `middleware` 34,8 %, `application` 43 %.

### Iteration 1 — cette campagne (2026-08-27)

| Ajout | Tests | Ou |
|-------|-------|----|
| Unitaire : JWT (7), middlewares auth / RBAC / rate-limit / CORS (11), services user et music (7), mock `MockMusicRepo` | 25 | `auth/`, `middleware/`, `application/`, `testutil/` |
| Integration base : 8 repositories + migrations, schema isole | 16 | `postgres/repos_integration_test.go`, `testutil/pgtest.go` |
| Integration API et securite : auth, matrice RBAC, flux avec auditeur SSE, playlists, favoris, musique (URL et multipart), admin, securite | 21 (dont 4 de securite) et 71 sous-tests | `internal/integration/` |
| Outillage | `make test-unit`, `make test-integration`, `make cover-check`, `-coverpkg` et seuil de couverture en CI | `Makefile`, `backend.yml` |
| Outillage mobile | `make test-mobile-cover`, seuil de couverture en CI (`scripts/coverage_check.sh`), rapport `lcov.info` en artefact | `Makefile`, `mobile/scripts/`, `mobile.yml` |

Resultat : 121 fonctions de test, couverture **75,6 %** (77,8 % hors
`cmd/server`, qui n'est pas testable unitairement). Quatre defauts trouves et
corriges (section 6), description OpenAPI completee (404 sur quatre
operations).

Couverture par paquet apres l'iteration :

| Paquet | Couverture | Paquet | Couverture |
|--------|-----------:|--------|-----------:|
| `transport/http` | 100 % | `application` | 82,9 % |
| `transport/http/middleware` | 93,4 % | `infrastructure/postgres` | 81,2 % |
| `infrastructure/auth` | 91,3 % | `domain` | 76,9 % |
| `infrastructure/config` | 88,2 % | `infrastructure/filestore` | 76,5 % |
| `transport/http/handlers` | 72,2 % | `infrastructure/streaming` | 68,2 % |
| `infrastructure/observability` | 56,5 % | `cmd/server` | 0 % |

### Iteration 2 — seuil a 80 % atteint (2026-08-30)

L'exigence du sujet « code testable unitairement a 80 % minimum » est
couverte et verrouillee : `COVERAGE_MIN` passe de 70 a 80 dans le `Makefile`
et dans `backend.yml`, la CI echoue desormais sous ce seuil.

| Ajout | Ou |
|-------|----|
| Branches d'erreur des handlers : requete sans claims (le middleware les pose toujours, seul l'appel direct les atteint), identifiant invalide, corps illisible, panne du depot simulee → `INTERNAL_ERROR` distinct des 404 | `handlers/*_unit_test.go` |
| Flux audio brut de bout en bout (`AudioStream`) : enregistrement au Hub, reception des octets par un vrai client HTTP, desenregistrement a la coupure ; diffuseur dont la connexion casse en plein direct | `handlers/stream_handler_unit_test.go` |
| Branches d'erreur des services (panne du depot sur chaque ecriture, relecture apres reordonnancement, refresh token orphelin, mot de passe > 72 octets refuse par bcrypt) et chemins restants (`ValidateToken`, `ListPublicPlaylists`, `UpdateStream`, `StopStream`, normalisation de pagination) | `application/service_errors_test.go` |
| Deadlines de connexion : erreurs reelles de `SetReadDeadline`/`SetWriteDeadline` propagees, upload refuse si la connexion ne les supporte pas | `handlers/handlers_unit_test.go`, `music_handler_unit_test.go` |
| Contrats des mocks aux bords (pagination au-dela du total, identifiants inconnus), regles du domaine (`StreamStatus`/`Role.IsValid`, hierarchie `AtLeast`), `MetricsAddr` | `testutil/mocks_pagination_test.go`, `domain/rules_test.go`, `config/addr_test.go` |

Resultat : couverture **91,1 %** (94,1 % hors `cmd/server`, qui n'est pas
testable unitairement). Couverture par paquet :

| Paquet | Couverture | Paquet | Couverture |
|--------|-----------:|--------|-----------:|
| `transport/http` | 100 % | `infrastructure/auth` | 91,3 % |
| `domain` | 100 % | `infrastructure/postgres` | 81,3 % |
| `transport/http/handlers` | 98,8 % | `infrastructure/filestore` | 76,5 % |
| `application` | 98,6 % | `infrastructure/observability` | 56,5 % |
| `infrastructure/streaming` | 97,7 % | `cmd/server` | 0 % |
| `infrastructure/config` | 96,2 % | `transport/http/middleware` | 93,5 % |

### Iteration 3 — couverture mobile a 80 % (2026-09-01)

L'exigence du sujet « code testable unitairement a 80 % minimum » est
desormais couverte et verrouillee cote Flutter aussi : `COVERAGE_MIN` passe
de 15 a 80 dans `mobile/scripts/coverage_check.sh`, la CI echoue desormais
sous ce seuil (`mobile.yml`).

Point de depart : 54 tests, 19,7 % — uniquement `core/audio`,
`shared/providers` et l'ecran console. Tout le reste de l'application
(repositories, providers metier, intercepteur HTTP, widgets, ecrans) tournait
sans le moindre test.

| Ajout | Ou | Gain |
|-------|----|-----:|
| Modeles de domaine et repositories (`music`, `stream`, `playlist`, `favorites`, `auth`) : parsing JSON, branches nominales et branches d'erreur HTTP par methode, via `mocktail` sur `Dio` | `test/features/*/data`, `test/features/*/domain` | 19,7 % → 28,0 % |
| Providers Riverpod (state notifiers), y compris les factories des providers eux-memes (`overrideWithValue` sur le repository plutot que sur le provider, pour exercer le vrai code de branchement) | `test/features/*/presentation/providers` | 28,0 % → 33,1 % |
| Intercepteur d'authentification de `api_client.dart` : bearer token, refresh sur 401 (succes, echec, absence de refresh token), rejeu de la requete d'origine ; `token_store_io.dart` (canal `flutter_secure_storage` simule) ; `validators.dart`, `extensions.dart` | `test/core/network/api_client_interceptors_test.dart`, `test/core/storage/`, `test/core/utils/` | 33,1 % → 35,6 % |
| Widgets partages et de features (`AppScaffold`, `MiniPlayer`, `VolumeControl`, `StreamCard`, `MusicTile`, `EditDialog`, etc.) | `test/shared/widgets`, `test/features/*/presentation/widgets` | 35,6 % → 47,4 % |
| Ecrans : favoris, playlists, admin, inscription, recherche, details stream/playlist, liste des streams, lecteur musique ; branches d'erreur residuelles des repositories | `test/features/*/presentation/screens` | 47,4 % → **80,1 %** |

Resultat : 394 tests, couverture **80,1 %**, `flutter analyze` sans avertissement.

#### Iteration 3bis — reconciliation avec la refonte UI (2026-09-01)

La branche avait divergé de `develop` juste avant la fusion de la refonte UI
(nouveau systeme de theme par `ThemeExtension`, consentement RGPD a
l'inscription, restructuration de `AppScaffold`/compte utilisateur, refactor
favoris/flux). La CI GitHub teste le merge de la PR avec la pointe de
`develop`, pas la branche seule : une reproduction locale de la branche seule
passait donc a chaque fois, masquant le vrai probleme jusqu'a ce que les logs
CI detailles montrent 17 erreurs de compilation deterministes.

| Etape | Detail |
|-------|--------|
| Fusion de `develop` | 96 fichiers, +4580/-1358 lignes, sans conflit (les fichiers de test etaient nouveaux) |
| Erreurs de compilation (17) | Nouveaux parametres requis (`acceptedTerms`, `trackCount`), signature de `StreamNotifier` (1 argument au lieu de 2, favoris extraits dans `FavoritesNotifier`), methode `toggleFavorite` supprimee |
| `flutter analyze` (39 problemes) | `theme:` desormais requis sur chaque `MaterialApp`/`MaterialApp.router` de test (sinon `context.colors` plante au premier rendu) → invalide le `const` de 19 fichiers, qui redevient necessaire sur les constructeurs internes (lint `prefer_const_constructors`, bloquant) |
| Echecs de test restants (23) | Libelles passes en francais (`OFFLINE`→`HORS LIGNE`, `Active Streams`→`Flux actifs`, nav `FAVORITES`→`FAVORIS`/`PROFILE`→`PROFIL`), suppression de compte deplacee vers `/account`, `LiveMiniPlayer` ajoute a `AppScaffold` (necessite `audioHandlerProvider` surcharge), icone favori plein vs contour selon l'ecran, `AudioWaveform` anime en continu sur un stream live et empeche `pumpAndSettle` de se stabiliser une fois une boite de dialogue ouverte par-dessus |
| Couverture apres fusion | La refonte a ajoute des ecrans et widgets entierement neufs et non testes (`account_screen.dart`, `privacy_policy_screen.dart`, `live_mini_player.dart`, `theme_provider.dart`) : couverture retombee a **71,7 %** malgre 428 tests verts |
| Tests ajoutes pour revenir a 80 % | `account_screen_test.dart` (13 tests : RGPD acces/effacement, rectification, preferences d'apparence), `privacy_policy_screen_test.dart`, `live_mini_player_test.dart`, `theme_provider_test.dart` (notifiers + stores `SharedPreferences`), `theme_test.dart` (`SPColors.copyWith`/`lerp`, themes contraste eleve), `router_test.dart` (redirections : route publique, session absente, garde admin/diffuseur, page 404), `audio_player_bar_test.dart`, complements a `playlist_provider_test.dart` (`PublicPlaylistNotifier`) et `volume_provider_test.dart` (`SharedPrefsVolumeStore`) |

Resultat : **455 tests**, couverture **80,4 %**, `flutter analyze` sans
avertissement, CI a nouveau verte.

Reste hors perimetre, a dessein — pas testable sans faire evoluer le code de
production d'abord :

| Fichier | Couverture | Raison |
|---------|-----------:|--------|
| `broadcaster_screen.dart` | 0,3 % | Enregistrement micro (`flutter_sound` recorder + `permission_handler`) |
| `live_stream_provider.dart`, methode `connect()` | 31,7 % (le reste de la classe est teste) | `HttpClient` et `AudioSession` instancies en dur dans le constructeur, non injectables |

Ces deux points demandent d'extraire la logique derriere une interface
injectable avant de pouvoir la tester unitairement — meme traitement que
celui applique a `api_client.dart` dans cette iteration. Reporte en
iteration 5.

Decouverte en cours de route, a reutiliser : `audioHandlerProvider` leve
volontairement une `UnimplementedError` si non surcharge (garde-fou deja en
place dans `lib/core/audio/audio_handler.dart`) — un simple
`ProviderScope(overrides: [audioHandlerProvider.overrideWithValue(fakeHandler)])`
suffit a rendre testables tous les widgets qui en dependent, y compris
`AudioPlayerBar` : `flutter_sound` ne plante pas dans l'environnement de
test, contrairement a ce qu'on aurait pu croire avant de l'essayer.

### Iteration 4 — planifiee (backend)

1. Completer `observability` (exporteur OTEL avec collecteur factice) et
   extraire de `cmd/server` un assemblage testable.
2. Traiter O-1 : alimenter `http_requests_total` et
   `http_request_duration_seconds` dans le middleware de logging, avec un test
   qui lit `/metrics` apres quelques requetes. Sans cela les SLO 1 et 2 de
   [slo.md](slo.md) ne sont pas mesurables.
3. Traiter O-2 : `http.MaxBytesReader` sur les corps JSON, test a 413.
4. `govulncheck` en CI (critere Ce3.3.4) et `flutter analyze` deja en place.
5. RGPD, suite de [rgpd.md](rgpd.md) section 6 : `PATCH /users/me`
   (rectification) et nettoyage des fichiers audio orphelins, chacun avec
   son test d'integration.

### Iteration 5 — planifiee

- Mobile : extraire la logique de `live_stream_provider.dart` (`connect()`)
  et de `broadcaster_screen.dart` derriere des interfaces injectables
  (`HttpClient`, `AudioSession`, recorder) pour les rendre testables
  unitairement ; a defaut, tests d'integration mobile (`integration_test`)
  sur simulateur contre la stack `docker compose`, un scenario par role.
- Fuzzing (`go test -fuzz`) des decodeurs JSON et de l'analyse des
  identifiants de chemin.
- Tests des migrations descendantes (`.down.sql`) : appliquer, revenir,
  reappliquer.
- Test de charge nocturne en CI (`make load-test`) avec suivi des chiffres
  de [scalability.md](scalability.md).

## 6. Anomalies relevees par la campagne

Chaque anomalie a d'abord ete un test rouge.

| Ref | Constat | Trouvee par | Gravite | Statut |
|-----|---------|-------------|---------|--------|
| A-01 | Rate limiting inoperant : la cle etait `IP:port`, donc un compteur neuf par connexion TCP | `TestRateLimiterKeyIgnoresSourcePort` | haute | **Corrigee** — `middleware/ratelimit.go` indexe sur l'hote seul |
| A-03 | `POST /streams/{inconnu}/start` et `/stop` repondaient 500 `INTERNAL_ERROR` au lieu de 404 | `TestStreams_OwnershipAndErrors/identifiant inconnu` | moyenne | **Corrigee** — `stream_handler.go`, OpenAPI |
| A-04 | `POST /playlists/{inconnu}/tracks` repondait 500 au lieu de 404 | `TestPlaylists_QueueManagement/suppression de la playlist` | moyenne | **Corrigee** — `playlist_handler.go`, OpenAPI |
| A-05 | `PUT /admin/users/{inconnu}/role` repondait 500 au lieu de 404 | `TestAdmin_UsersAndRoles/changement de role refuse` | moyenne | **Corrigee** — `admin_handler.go`, OpenAPI |

Observations a arbitrer, non corrigees dans cette iteration :

| Ref | Observation | Impact | Proposition |
|-----|-------------|--------|-------------|
| O-1 | `http_requests_total` et `http_request_duration_seconds` sont declares dans `observability/metrics.go` mais jamais incrementes | Les SLI des SLO 1 et 2 de [slo.md](slo.md) sont vides ; le dashboard Grafana ne montre ni trafic ni latence | Incrementer dans le middleware de logging (iteration 2) |
| O-2 | Aucune limite de taille sur les corps JSON ; le multipart n'est borne qu'en memoire (32 Mio) | Un client peut envoyer un corps arbitrairement grand | `http.MaxBytesReader` + variable `MAX_BODY_BYTES` |
| O-3 | `CORS_ALLOWED_ORIGINS=*` avec `AllowCredentials: true` dans la stack de dev | Acceptable en local, a restreindre en production | **Corrigee** — le joker n'annonce plus les credentials (`middleware/cors.go`), `APP_ENV=production` refuse le joker au demarrage (`config.go`), et `docker-compose.prod.yml` exige une liste d'origines |
| O-4 | `PUT`/`DELETE` sur la playlist privee d'un tiers repondent 403, alors que `GET` repond 404 | L'existence d'un identifiant est revelee par les methodes d'ecriture | Aligner sur 404, ou assumer et documenter |
| A-02 | `HEAD /health` repond 405 (cahier de recette) | Sans effet sur les sondes actuelles (`GET`) | `chi/middleware.GetHead` |

## 7. Execution

```bash
# Suite unitaire, sans base
cd backend && make test-unit

# Suite d'integration : une base PostgreSQL jetable suffit
createdb streampulse_test                       # ou : docker compose up -d postgres
export DATABASE_URL=postgres://localhost:5432/streampulse_test?sslmode=disable
make test-integration

# Tout, avec le seuil de couverture de la CI
make cover-check                                # echoue sous 80 %, comme la CI

# Mobile, avec le seuil de couverture de la CI
cd .. && make test-mobile-cover           # echoue sous 80 %, comme la CI
```

En CI (`.github/workflows/backend.yml`), le job `test` demarre un service
PostgreSQL, exporte `DATABASE_URL`, execute `go test -race -coverpkg=./...`
puis le seuil de couverture. Les jobs `lint` (golangci-lint) et `openapi`
(redocly) tournent en parallele ; `build` n'est lance que si les trois sont
verts. Cote mobile (`mobile.yml`), le job `test` execute
`flutter test --coverage` puis `scripts/coverage_check.sh` ; les builds APK,
iOS et web n'ont lieu que s'il est vert. Dans les deux workflows, le chiffre
de couverture apparait dans le resume du job et le rapport est telechargeable
en artefact de la PR.

### Criteres d'entree et de sortie d'une iteration

| | Critere |
|---|---------|
| Entree | Cas d'usage identifies dans la section 3 ; tests ecrits ou modifies dans la PR qui porte le code |
| Sortie | CI verte (lint, contrat, tests unitaires et d'integration, seuil de couverture) ; aucun test ignore de facon inattendue ; anomalies trouvees consignees dans la section 6 avec leur test ; `CHANGELOG.md` mis a jour |
