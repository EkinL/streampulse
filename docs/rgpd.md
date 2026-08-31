# Donnees personnelles et RGPD

Ce document decrit ce que StreamPulse conserve sur une personne, pourquoi,
combien de temps, comment elle exerce ses droits, et quelles mesures
protegent ces donnees. Il repond au critere Ce3.1.4 du bloc 3 (contraintes de
securite et reglementaires). Une synthese en anglais figure en fin de document.

## 1. Perimetre

StreamPulse est une plateforme de diffusion audio avec quatre roles
(`anonymous`, `user`, `broadcaster`, `admin`). Le responsable de traitement est
l'equipe projet ; il n'y a ni sous-traitant ni transfert hors Union europeenne
dans la stack livree (`docker-compose.yml`). Les donnees ne sont ni vendues ni
transmises a un tiers.

## 2. Registre des traitements

| Donnee | Ou | Finalite | Base legale | Conservation |
|--------|----|----------|-------------|--------------|
| Email, nom d'utilisateur | table `users` | Identifier le compte, se connecter | Execution du contrat (creation du compte) | Duree de vie du compte |
| Mot de passe | table `users`, **hash bcrypt (cout 12)** uniquement | Authentification | Execution du contrat | Duree de vie du compte |
| Role, dates de creation et de mise a jour | table `users` | Autorisation, tracabilite du compte | Execution du contrat | Duree de vie du compte |
| Refresh tokens | table `refresh_tokens`, **hash SHA-256** uniquement | Prolonger une session sans ressaisir le mot de passe | Execution du contrat | 168 h maximum (`JWT_REFRESH_EXPIRY`), revoques a chaque connexion, **purges automatiquement une fois expires** (`REFRESH_TOKEN_PURGE_INTERVAL`, 1 h) |
| Flux, playlists, favoris, morceaux deposes | tables `streams`, `playlists`, `tracks`, `favorites`, `music`, `music_favorites` | Le service lui-meme | Execution du contrat | Duree de vie du compte, **supprimes en cascade avec lui** |
| Adresse IP, user-agent, chemin, statut, `request_id`, `trace_id` | logs JSON sur la sortie standard du conteneur `api` | Securite (rate limiting par hote), diagnostic | Interet legitime | Fixee par la plateforme de logs qui les collecte : journal Docker en local, retention a configurer sur le collecteur en production (recommandation : 30 jours) |
| Traces OpenTelemetry | collecteur OTEL | Diagnostic de performance | Interet legitime | Fixee par le backend de traces ; les spans ne portent ni email ni identifiant de compte |
| Metriques Prometheus | `/metrics` (admin) et listener interne | Supervision | Interet legitime | Agregees, aucune donnee individuelle |

Ce que la plateforme **ne collecte pas** : historique d'ecoute, position
geographique, identifiants publicitaires, cookies tiers, donnees de paiement.
L'application mobile ne conserve localement que le couple de jetons, dans le
stockage securise du systeme (`core/storage/secure_storage.dart`).

## 3. Droits des personnes

| Droit | Comment l'exercer | Ou dans le code |
|-------|-------------------|-----------------|
| Acces (art. 15) et portabilite (art. 20) | `GET /users/me` renvoie, au format JSON, l'integralite des donnees du compte lues en base | `handlers/user_handler.go` |
| Effacement (art. 17) | `DELETE /users/me`, ou dans l'application mobile : avatar > **Delete my account**, apres confirmation. Le compte et tout ce qui s'y rattache disparaissent immediatement, par cascade en base | `handlers/user_handler.go`, `postgres/user_repo.go`, migrations `ON DELETE CASCADE` |
| Effacement sur demande hors application | Un administrateur supprime le compte avec `DELETE /admin/users/{id}` | `handlers/admin_handler.go` |
| Rectification (art. 16) | `PATCH /users/me` avec `email` et `username`. Les deux champs sont requis et remplacent la valeur en cours ; l'unicite de l'email est verifiee comme a l'inscription | `handlers/user_handler.go`, `application/user_service.go`, `postgres/user_repo.go` |
| Opposition, limitation | Sans objet : aucun traitement ne repose sur le consentement ni sur du profilage | — |

Apres un effacement, le jeton d'acces encore detenu par l'application reste
valide cryptographiquement jusqu'a son expiration (15 minutes, [ADR 006](ADR/006-strategie-auth-jwt.md))
mais ne designe plus aucun compte : `GET /users/me` repond 404, le refresh
token a ete supprime avec le compte, et l'email est immediatement disponible
pour une nouvelle inscription. Ce comportement est verifie par
`TestUsers_AccessAndErasure` et `TestAdmin_DeleteUser`
(`backend/internal/integration/users_test.go`) et par
`TestCascadeOnUserDelete` (`backend/internal/infrastructure/postgres`).

Le choix d'un effacement physique plutot que d'une anonymisation est justifie
dans l'[ADR 007](ADR/007-effacement-compte-rgpd.md).

## 4. Politique de retention

- **Compte et contenus** : conserves tant que le compte existe, supprimes en
  cascade a l'effacement. Aucune copie de sauvegarde n'est prise par la stack
  livree ; si une sauvegarde PostgreSQL est mise en place en production, sa
  rotation doit etre documentee et rester courte (30 jours recommandes).
- **Refresh tokens** : 168 heures au plus. Une connexion revoque les jetons
  precedents du compte, un rafraichissement consomme le jeton presente, et une
  tache de fond (`application.PurgeExpiredRefreshTokens`, lancee dans
  `cmd/server/main.go`) supprime les jetons expires au demarrage puis toutes
  les `REFRESH_TOKEN_PURGE_INTERVAL`.
- **Logs et traces** : la retention est celle de la plateforme d'observabilite
  ; elle doit etre configuree explicitement en production.
- **Donnees de developpement** : les comptes du seed (`backend/scripts/seed.sql`)
  sont fictifs (`@streampulse.io`). Aucune adresse ni donnee reelle ne figure
  dans le depot, et le seed ne doit jamais etre joue sur un environnement
  expose.

## 5. Mesures de securite

| Mesure | Ou |
|--------|----|
| Mots de passe haches en bcrypt (cout 12), jamais renvoyes par l'API | `application/auth_service.go`, `TestAuth_SecretsAreStoredHashed` |
| Jetons d'acces courts (15 min), refresh tokens opaques, a usage unique, stockes haches | [ADR 006](ADR/006-strategie-auth-jwt.md) |
| Chiffrement en transit : HTTPS natif (`TLS_CERT_FILE` / `TLS_KEY_FILE`, TLS 1.2 minimum) ou terminaison TLS sur un reverse proxy ; `sslmode=require` vers PostgreSQL en production | `cmd/server/main.go`, [deployment.md](deployment.md) |
| `/metrics` reserve au role `admin` ; Prometheus scrute un listener interne non publie | `transport/http/router.go`, `TestMetricsAccess` |
| Controle d'acces par role et par propriete sur chaque route | `middleware/rbac.go`, `TestRBAC_EndpointMatrix` |
| Rate limiting par hote | `middleware/ratelimit.go` |
| Requetes SQL parametrees (pgx), aucune concatenation | `infrastructure/postgres/*`, `TestSecurity_SQLInjectionIsNeutralised` |
| Refus des champs JSON inconnus (pas de mass assignment) | `handlers/response.go` (`DisallowUnknownFields`), `TestSecurity_UnknownFieldsRejected` |
| Origines CORS nommees : le joker `*` est refuse au demarrage en production, et n'annonce jamais `Allow-Credentials` | `CORS_ALLOWED_ORIGINS`, `config/config.go`, `middleware/cors.go`, `TestLoadRejectsWildcardCORSInProduction` |
| Reverse proxy Caddy en production : TLS termine, API non publiee, PostgreSQL et collecteur non exposes, `X-Forwarded-For` cru seulement depuis `TRUSTED_PROXIES` | `docker-compose.prod.yml`, `caddy/Caddyfile`, `middleware/ratelimit.go` |
| Aucun secret dans le depot : tout passe par des variables d'environnement, `backend/.env` est ignore par git | `config/config.go`, `.env.example` |
| Image Docker minimale (multi-stage, alpine, binaire `-s -w`) | `backend/Dockerfile` |

## 6. Limites connues et suite

1. **Fichiers audio** : la suppression d'un compte efface les lignes `music`
   mais laisse les fichiers deposes dans `uploads/`, qui restent servis a
   leur URL par `/uploads/{fichier}` pour qui la connait. Ils ne contiennent
   pas de donnees personnelles, mais un nettoyage des fichiers orphelins est
   a prevoir (meme limite que `DELETE /music/{id}`).
2. **Consentement et information** : l'application ne presente pas encore de
   conditions d'utilisation ni de lien vers ce document a l'inscription.
3. **Delai de retractation** : l'effacement est immediat et irreversible. Un
   delai de grace (compte desactive puis purge a J+30) est une evolution
   possible, au prix d'une colonne `deleted_at` et d'une tache de purge.
4. **Retention des logs** : dependante de la plateforme de collecte, a
   contractualiser lors de la mise en production.

---

## Summary (English)

StreamPulse stores, per account: email, username, a bcrypt password hash, a
role and timestamps; SHA-256 hashes of refresh tokens (max 168 h, revoked on
login, purged automatically once expired); and the user's streams, playlists,
favorites and uploaded tracks. HTTP logs carry the client IP and user agent
for security and diagnostics; their retention is set by the log platform.
No listening history, location, advertising identifiers or third-party
trackers are collected.

Rights: `GET /users/me` returns every piece of personal data held (access and
portability); `PATCH /users/me` rectifies the email or username; `DELETE
/users/me` — or **Delete my account** in the mobile app — erases the account
and everything attached to it immediately, by database cascade; an admin can
delete an account on behalf of a user with `DELETE /admin/users/{id}`.

Security: bcrypt 12, short-lived JWTs with single-use hashed refresh tokens,
TLS (native or via a reverse proxy), admin-only `/metrics`, role- and
ownership-based access control, per-host rate limiting, parameterised SQL,
strict JSON decoding, no secrets in the repository.
