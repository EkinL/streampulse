# Cahier de recette

Ce document decrit la strategie de test de StreamPulse, puis les cas de recette
de l'API et leur resultat **reellement observe**.

Les colonnes « resultat obtenu » ne sont pas des copies de la colonne
« attendu » : chaque cas a ete execute contre la stack en fonctionnement, et le
code HTTP et le corps de reponse ci-dessous sont ceux que le serveur a renvoyes.
**Deux cas echouent** et sont documentes comme tels.

## 1. Strategie de test

La strategie complete — niveaux, cartographie cas d'usage → tests, campagne
de securite, iterations et seuils — est dans le
[plan de tests iteratifs](plan-de-tests.md). Ce cahier n'en garde que le
resume et consigne les resultats **reellement observes** de la recette
manuelle.

### Ce qui est teste, et a quel niveau

| Niveau | Perimetre | Outillage | Ou |
|--------|-----------|-----------|-----|
| Unitaire | Regles metier pures, sans I/O : services applicatifs, validation, hierarchie de roles, JWT, middlewares, parsing d'erreurs | `testing`, mocks de repository | `internal/application`, `internal/infrastructure`, `internal/transport/http/middleware` |
| Contrat | Le routeur et la description OpenAPI : routes documentees, 401 sur les operations `bearerAuth`, correlation des requetes | `chi.Walk`, `httptest` | `internal/transport/http` |
| Integration base | Les repositories contre un vrai PostgreSQL : unicite, cascades, expiration, plein texte, transactions | `DATABASE_URL`, schema isole par paquet | `internal/infrastructure/postgres/repos_integration_test.go` |
| Integration API | Le serveur complet, middlewares compris, par HTTP reel et par role | `httptest.Server` + PostgreSQL | `internal/integration` |
| Securite | Jetons forges, injection SQL, mass assignment, matrice RBAC, propriete, rate limiting, secrets haches | memes outils | `auth/jwt_test.go`, `middleware/*_test.go`, `integration/security_test.go` |
| Charge | Le Hub de fan-out sous concurrence reelle | benchmarks Go, `-race` | branche `test/hub-load-proof` |
| Recette | L'API telle qu'un client la consomme, par role | ce document | — |

### Principes

**Les tests sont ecrits avec le code, pas apres.** Chaque PR qui ajoute un
comportement ajoute le test qui le decrit. La regle est verifiable : la CI
echoue sous le seuil de couverture (`COVERAGE_MIN`, voir le plan de tests).

**Les cas d'echec comptent autant que les cas nominaux.** Sur les 48 cas
ci-dessous, 21 verifient un refus : mauvais mot de passe, role insuffisant,
non-proprietaire, identifiant invalide, jeton rejoue. Un chemin nominal qui
fonctionne ne prouve rien sur ce qui se passe quand un utilisateur sort du
scenario prevu.

**Ce qui ne peut pas etre teste par un mock ne l'est pas.** Les repositories
PostgreSQL sont testes contre une vraie base : un mock de `pgx` ne validerait ni
les contraintes d'unicite, ni les cascades, ni le comportement transactionnel du
reordonnancement de playlist, c'est-a-dire precisement ce pour quoi PostgreSQL a
ete choisi ([ADR 005](ADR/005-choix-postgresql.md)).

**La description OpenAPI est verifiee contre le routeur.** Un test parcourt les
routes reellement enregistrees et echoue si une route n'est pas decrite, ou si
une operation decrite n'existe plus.

## 2. Conditions d'execution

| | |
|---|---|
| Stack | `docker compose up -d --build` |
| API | `http://localhost:8080` |
| Base | PostgreSQL 16, migrations appliquees au demarrage |
| Rate limit | `RATE_LIMIT_RPS=10`, `RATE_LIMIT_BURST=20` |
| Date d'execution | 2026-08-27 |

### Prerequis : creation des roles

Les comptes `user` sont crees par l'API. **Il n'existe aucun moyen de creer le
premier compte `broadcaster` ou `admin` par l'API** : `PUT /admin/users/{id}/role`
exige deja d'etre admin. L'amorcage passe donc par la base :

```sql
UPDATE users SET role='broadcaster' WHERE id='<uuid>';
UPDATE users SET role='admin'       WHERE id='<uuid>';
```

Il faut ensuite **se reconnecter** : les claims sont figes a l'emission du jeton,
une promotion ne prend effet qu'au jeton suivant
([ADR 006](ADR/006-strategie-auth-jwt.md)).

> C'est une limite du produit, pas du cahier de recette : un deploiement neuf
> n'a aucun administrateur et aucun moyen d'en creer un sans acces SQL.
> `backend/scripts/seed.sql` fournit un compte de developpement, mais il n'est
> pas monte par `docker-compose.yml` et n'est donc pas applique automatiquement.

## 3. Cas de recette

Legende : **OK** le resultat obtenu correspond a l'attendu — **ECHEC** il en
differe.

### 3.1 Systeme

| Cas | Requete | Role | Attendu | Obtenu | |
|-----|---------|------|---------|--------|---|
| R-01 | `GET /health` | anonyme | 200, `status: ok` | 200, `{"data":{"status":"ok"},"meta":{…}}` | OK |
| R-02 | `GET /openapi.yaml` | anonyme | 200, `application/yaml` | 200, `application/yaml; charset=utf-8` | OK |
| R-03 | `GET /docs` | anonyme | 200, `text/html` | 200, `text/html; charset=utf-8` | OK |

### 3.2 Authentification

| Cas | Requete | Role | Attendu | Obtenu | |
|-----|---------|------|---------|--------|---|
| R-10 | `POST /auth/register` nouveau compte | anonyme | 201 + couple de jetons | 201, `access_token` + `refresh_token` + `user` | OK |
| R-11 | `POST /auth/register` email deja pris | anonyme | 409 `CONFLICT` | 409, `{"error":{"code":"CONFLICT"…}}` | OK |
| R-12 | `POST /auth/register` champ JSON inconnu | anonyme | 400 `BAD_REQUEST` | 400, `{"error":{"code":"BAD_REQUEST"…}}` | OK |
| R-13 | `POST /auth/login` mot de passe correct | anonyme | 200 + jetons | 200, `access_token` emis | OK |
| R-14 | `POST /auth/login` mauvais mot de passe | anonyme | 401 `UNAUTHORIZED` | 401, `{"error":{"code":"UNAUTHORIZED"…}}` | OK |
| R-15 | `POST /auth/refresh` jeton valide | anonyme | 200 + nouveau couple | 200, nouveau `access_token` | OK |
| R-16 | `POST /auth/refresh` **rejeu du meme jeton** | anonyme | 401 — usage unique | 401, `{"error":{"code":"UNAUTHORIZED"…}}` | OK |
| R-17 | `GET /playlists` sans en-tete `Authorization` | anonyme | 401 | 401 | OK |
| R-18 | `GET /playlists` jeton malforme | anonyme | 401 | 401 | OK |

R-16 est le cas qui prouve la rotation a usage unique du refresh token : le
jeton presente est consomme, le rejouer echoue.

### 3.3 Consultation anonyme

| Cas | Requete | Role | Attendu | Obtenu | |
|-----|---------|------|---------|--------|---|
| R-20 | `GET /streams` | anonyme | 200 pagine | 200, `{"data":[],"meta":{…}}` | OK |
| R-21 | `GET /streams/{uuid inconnu}` | anonyme | 404 `NOT_FOUND` | 404 | OK |
| R-22 | `GET /streams/pas-un-uuid` | anonyme | 400 `BAD_REQUEST` | 400 | OK |
| R-23 | `GET /music` | anonyme | 200 pagine | 200, `{"data":[],…}` | OK |
| R-24 | `GET /search` sans `q` | anonyme | 400 `INVALID_INPUT` | 400, `{"error":{"code":"INVALID_INPUT"…}}` | OK |
| R-25 | `GET /search?q=jazz` | anonyme | 200, `{streams, music}` | 200, `{"data":{"streams":[],"music":[]}}` | OK |

### 3.4 Diffusion

| Cas | Requete | Role | Attendu | Obtenu | |
|-----|---------|------|---------|--------|---|
| R-50 | `POST /streams` | broadcaster | 201, statut `idle` | 201, flux cree | OK |
| R-41 | `POST /streams` | **user** | 403 — role insuffisant | 403, `{"error":{"code":"FORBIDDEN"…}}` | OK |
| R-57 | `GET /streams/{id}/listen` sur un flux `idle` | user | 400 `STREAM_NOT_LIVE` | 400, `{"error":{"code":"STREAM_NOT_LIVE"…}}` | OK |
| R-51 | `POST /streams/{id}/start` | broadcaster | 200, `status: live` | 200, `{"data":{"status":"live"}}` | OK |
| R-52 | `POST /streams/{id}/start` deja live | broadcaster | 409 `CONFLICT` | 409 | OK |
| R-54 | `GET /streams/{id}/listeners` | user | 200, compte a 0 | 200, `{"count":0,"listeners":[]}` | OK |
| R-56 | `PUT /streams/{id}` d'un **autre** proprietaire | admin | 403 — non-proprietaire | 403, `{"error":{"code":"FORBIDDEN"…}}` | OK |
| R-55 | `POST /streams/{id}/stop` | broadcaster | 200, `status: stopped` | 200 | OK |

R-56 est important : le compte est **admin**, donc son role est suffisant, mais
il n'est pas proprietaire du flux. Il verifie que la propriete est controlee
separement du role, et non confondue avec lui.

### 3.5 Playlists et favoris

| Cas | Requete | Role | Attendu | Obtenu | |
|-----|---------|------|---------|--------|---|
| R-30 | `GET /playlists` | user | 200 pagine | 200, `{"data":[],…}` | OK |
| R-31 | `POST /playlists` | user | 201 | 201, playlist creee | OK |
| R-33 | `POST /playlists/{id}/tracks` | user | 201, piste positionnee | 201 | OK |
| R-32 | `GET /playlists/{id}` | user | 200 + pistes ordonnees | 200, 2 pistes | OK |
| R-34 | `PUT /playlists/{id}/tracks` ordre inverse | user | 200, positions reecrites | 200, playlist reordonnee | OK |
| R-35 | `PUT /playlists/{id}/tracks` **liste incomplete** | user | 400 | 400, `{"error":{"code":"BAD_REQUEST"…}}` | OK |
| R-37 | `GET /playlists/{id}` **privee, autre utilisateur** | broadcaster | **404**, pas 403 | 404, `{"error":{"code":"NOT_FOUND"…}}` | OK |
| R-36 | `DELETE /playlists/{id}/tracks/{trackId}` | user | 200 | 200, `{"status":"removed"}` | OK |
| R-38 | `POST /favorites/{streamId}` | user | 201 | 201, `{"status":"added"}` | OK |
| R-39 | `GET /favorites` | user | 200, le flux favori | 200, 1 element | OK |
| R-40 | `DELETE /favorites/{streamId}` | user | 200 | 200, `{"status":"removed"}` | OK |

R-37 verifie une decision de securite deliberee : une playlist privee dont on
n'est pas proprietaire repond **404** et non 403, pour qu'un 403 ne confirme pas
l'existence de l'identifiant.

R-35 verifie que le reordonnancement exige la liste **complete** des pistes :
une liste partielle est refusee plutot que d'etre appliquee a moitie.

### 3.6 Administration

| Cas | Requete | Role | Attendu | Obtenu | |
|-----|---------|------|---------|--------|---|
| R-60 | `GET /admin/users` | admin | 200 pagine | 200, liste des comptes | OK |
| R-61 | `GET /admin/users` | user | 403 | 403 | OK |
| R-62 | `PUT /admin/users/{id}/role` role valide | admin | 200 | 200, `{"status":"updated"}` | OK |
| R-63 | `PUT /admin/users/{id}/role` role `sorcier` | admin | 400 | 400, `{"error":{"code":"BAD_REQUEST"…}}` | OK |
| R-64 | `GET /metrics` | admin | 200, format Prometheus | 200, `# HELP active_listeners …` | OK |
| R-65 | `GET /metrics` | user | 403 | 403 | OK |
| R-66 | `GET /metrics` sans jeton | anonyme | 401 | 401 | OK |

### 3.7 Securite

| Cas | Requete | Role | Attendu | Obtenu | |
|-----|---------|------|---------|--------|---|
| R-70 | `GET /search?q=' OR 1=1--` | anonyme | 200, aucune fuite | 200, `{"streams":[],"music":[]}` | OK |
| R-71 | `POST /playlists` avec un champ inconnu | user | 400 | 400 | OK |
| R-72 | **60 requetes en rafale sur `/health`** | anonyme | des `429` apres 20 | **60 x 200, aucun 429** | **ECHEC** |
| R-73 | **`HEAD /health`** | anonyme | 200 | **405** | **ECHEC** |

## 4. Anomalies relevees

### A-01 — Le rate limiting est inoperant (R-72) — severite haute

**Symptome.** 60 requetes en rafale sur `/health` renvoient toutes 200, alors
que `RATE_LIMIT_RPS=10` et `RATE_LIMIT_BURST=20`. Mesure : 60 requetes
sequentielles passent a **152 req/s** sans le moindre refus.

**Cause.** `middleware/ratelimit.go` indexe ses compteurs sur `r.RemoteAddr` :

```go
ip := r.RemoteAddr
if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
    ip = forwarded
}
limiter := rl.getLimiter(ip)
```

`r.RemoteAddr` vaut `IP:PORT`, et **le port source change a chaque connexion
TCP**. Chaque requete recoit donc une cle differente, donc un compteur neuf
avec son burst complet. La limite n'est jamais atteinte.

**Preuve.** Avec une cle stable, le limiteur fonctionne parfaitement :

```
$ for i in $(seq 1 40); do curl -s -o /dev/null -w '%{http_code}\n' \
    -H 'X-Forwarded-For: 10.9.9.9' http://localhost:8080/health; done | sort | uniq -c
  22 200
  18 429
```

22 passages (burst de 20 + deux recharges) puis 18 refus : le token bucket est
correct, c'est **la cle qui est fausse**.

**Correctif.** Extraire l'hote seul avec `net.SplitHostPort(r.RemoteAddr)`.

**Statut : corrigee.** `middleware/ratelimit.go` indexe desormais sur l'hote
seul ; le test `TestRateLimiterKeyIgnoresSourcePort` (deux ports, meme hote,
meme compteur) etait rouge avant le correctif et garde le comportement.

**Remarque connexe.** `X-Forwarded-For` est utilise sans condition. Tant que la
stack n'a pas de reverse-proxy de confiance, n'importe quel client peut en
envoyer un arbitraire pour obtenir un compteur vierge, ou usurper l'adresse d'un
tiers pour le faire limiter a sa place. L'en-tete ne devrait etre pris en compte
que derriere un proxy identifie.

### A-02 — `HEAD` n'est pas route (R-73) — severite faible

`HEAD /health` renvoie **405**, alors que `GET /health` renvoie 200. Le routeur
chi n'associe pas automatiquement `HEAD` aux handlers `GET`. Sans consequence
aujourd'hui — le `HEALTHCHECK` du Dockerfile et la sonde de la CI utilisent
`GET` — mais un orchestrateur configure en `HEAD` conclurait a tort que le
service est mort.

## 5. Synthese

| | Cas | |
|---|---:|---|
| Executes | **48** | |
| Conformes | **46** | 96 % |
| En echec | **2** | A-01 (haute, corrigee depuis), A-02 (faible) |
| Dont cas de refus attendu | 21 | 44 % des cas |

Les 46 cas conformes couvrent les quatre roles, les six domaines fonctionnels et
les principaux codes d'erreur de la description OpenAPI.

## 6. Rejouer cette recette

La stack doit tourner (`docker compose up -d`), puis chaque cas se rejoue tel
quel avec `curl`. Exemple pour R-16, le rejeu de refresh token :

```bash
API=http://localhost:8080
TOK=$(curl -s -X POST $API/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"…","password":"…"}' \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["refresh_token"])')

curl -s -o /dev/null -w '%{http_code}\n' -X POST $API/auth/refresh \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$TOK\"}"   # 200
curl -s -o /dev/null -w '%{http_code}\n' -X POST $API/auth/refresh \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$TOK\"}"   # 401
```

Les cas automatises correspondants vivent dans `backend/internal/integration`
et `backend/internal/transport/http` ; ils se lancent avec
`cd backend && make test-integration` (voir le [plan de tests](plan-de-tests.md)).
