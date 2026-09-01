# ADR 005: Timeouts HTTP globaux, leves par connexion pour les flux

## Statut
Accepted

## Contexte
Trois routes gardent la connexion ouverte pendant toute la duree d'un live :
- `GET /streams/{id}/listen` (SSE) et `GET /streams/{id}/audio` (PCM brut) ecrivent en continu vers l'auditeur
- `POST /streams/{id}/broadcast` lit en continu le corps envoye par le diffuseur

Jusqu'ici `http.Server` tournait avec `ReadTimeout: 0` et `WriteTimeout: 0` pour ne pas couper ces trois routes. Le prix : aucune des autres routes n'avait de timeout non plus. Un client qui ouvre une connexion et n'envoie jamais la fin de ses headers (slowloris), ou qui poste un JSON de 10 octets a 1 octet par minute, occupe une goroutine et un file descriptor pour toujours. A l'arret du serveur, `Shutdown` attendait aussi les 30 secondes completes parce que les boucles SSE ne rendent jamais la main d'elles-memes.

## Decision
Les timeouts sont **globaux et actifs par defaut**, configurables par variables d'environnement (`HTTP_READ_TIMEOUT` 30s, `HTTP_WRITE_TIMEOUT` 30s, `HTTP_IDLE_TIMEOUT` 60s) plus un `ReadHeaderTimeout` de 5s fixe contre le slowloris.

Les trois handlers de flux **levent les deadlines pour leur seule connexion** via `http.NewResponseController(w).SetReadDeadline / SetWriteDeadline(time.Time{})` (helper `keepConnectionOpen` dans `handlers/deadline.go`). C'est l'API prevue par la stdlib depuis Go 1.20 pour exactement ce cas ; elle traverse les middlewares grace a `Unwrap()` sur notre `responseWriter`.

L'upload de musique (`POST /music`, 32 Mo max) n'est pas un flux mais peut depasser 30s depuis un mobile : il repousse ses deadlines a 2 minutes avec `extendDeadlines`. Les deux deadlines, pas seulement la lecture : `WriteTimeout` court depuis la fin des headers, la reponse `201` d'un upload de 90s partirait apres expiration.

La sortie des boucles de flux reste pilotee par le contexte :
- `r.Context()` est annule quand le client part, et a l'arret du serveur via `BaseContext` (`main.go` annule ce contexte juste avant `srv.Shutdown`, les boucles sortent, les connexions passent idle et `Shutdown` rend la main tout de suite)
- `client.Done()` est ferme quand le stream est arrete ou le client evince par le hub
- `Broadcast` est bloque dans `r.Body.Read`, qui en HTTP/1.1 ne regarde pas le contexte : `unblockReadOnCancel` pose une deadline de lecture immediate (`context.AfterFunc`) des que le contexte est annule, le `Read` echoue et le handler sort. Sans ca un diffuseur silencieux tiendrait la connexion pendant tout le delai de `Shutdown`

Le callback `OnListenerChange`, appele hors requete par le hub, pose lui-meme un `context.WithTimeout` de 5s sur son ecriture en base : sans parent, une base qui ne repond plus laisserait s'accumuler une goroutine par changement d'audience.

## Alternatives ecartees
- **Garder les timeouts a 0 et documenter** : c'est le statu quo, la surface d'attaque reste entiere pour 30 routes afin d'en proteger 3.
- **Deux `http.Server` (un pour l'API, un pour les flux)** : deux ports, deux configs CORS/auth/rate-limit a garder synchrones, et le client mobile devrait connaitre les deux. Beaucoup de complexite pour un resultat que `ResponseController` donne en trois lignes.
- **`http.TimeoutHandler` par route** : ne gere que l'ecriture, bufferise la reponse (incompatible avec le flush SSE) et ne touche pas au `ReadTimeout`.
- **Timeouts longs mais finis sur les flux (ex. 4h)** : un live n'a pas de duree maximale connue, et un auditeur coupe sec en plein milieu sans raison metier est un bug, pas une protection.

## Consequences
- Les routes classiques sont bornees ; un client lent ou malveillant libere sa goroutine au bout de 30s au plus.
- `docker compose down` et un redeploiement ne bloquent plus 30s sur les auditeurs connectes.
- Si `SetReadDeadline` echoue (ResponseWriter non deballable), le flux fonctionne quand meme mais sera coupe a `WriteTimeout` : un warning est logue pour le voir tout de suite plutot que de chercher pourquoi tous les auditeurs decrochent a la meme seconde.
- Tout nouveau handler de flux doit appeler `keepConnectionOpen` ; les tests de `deadline_test.go` (serveur avec timeouts de 150ms, handler qui tient 450ms) documentent le comportement attendu et le cas temoin sans l'appel.

---

## Summary (English)

Three routes must hold their connection open for an entire live broadcast
(SSE and raw-audio listening, chunked broadcast upload), which previously
forced `ReadTimeout`/`WriteTimeout` to 0 **globally** — leaving every other
route vulnerable to slowloris attacks or a client that trickles a request
body forever, and making graceful shutdown wait the full 30 seconds since
SSE loops never yield on their own. The fix: global timeouts are on by
default (30s read/write, 60s idle, 5s header-read against slowloris), and
only the three streaming handlers lift the deadline **for their own
connection** via `http.NewResponseController` (`SetReadDeadline`/
`SetWriteDeadline` with a zero time) — the standard-library mechanism
provided since Go 1.20 for exactly this case. Music uploads get a 2-minute
extension instead of an unlimited one. Loop exit is driven by context
cancellation everywhere, including a deliberate trick for
`POST /broadcast`: since HTTP/1.1's `r.Body.Read` ignores context
cancellation, `unblockReadOnCancel` sets an immediate read deadline via
`context.AfterFunc` the moment the context is cancelled, forcing the read
to fail and the handler to exit. Rejected alternatives included keeping
timeouts at zero everywhere, running two separate `http.Server`s, and
`http.TimeoutHandler` (which buffers responses, breaking SSE flushing).
