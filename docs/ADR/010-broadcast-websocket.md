# ADR 010: WebSocket pour l'ingest audio du diffuseur

## Statut
Accepted

## Contexte
L'ADR 003 a retenu, cote diffuseur, un `POST /streams/{id}/broadcast` chunke :
le corps de la requete est le flux audio, lu au fil de l'eau. Cela fonctionne
depuis l'app mobile (dart:io ecrit chaque chunk sur la socket des qu'il
arrive), mais pas depuis la console web des diffuseurs : dans un navigateur,
Dio passe par `XMLHttpRequest`, qui n'accepte qu'un corps complet. L'adaptateur
accumule tout le flux en memoire et n'appelle `send()` qu'a la fermeture du
flux, c'est-a-dire a la fin du live. Le serveur ne recevait donc jamais rien
pendant le direct, et les auditeurs restaient sur « Connected - Waiting for
audio... » alors que la console affichait « connecte ». Le probleme n'apparait
qu'en production, ou les diffuseurs utilisent la console web ; en
developpement, le diffuseur est teste depuis le simulateur iOS.

Les corps de requete en flux existent dans `fetch` (`duplex: 'half'`) mais
seulement en HTTP/2 ou HTTP/3, et pas dans tous les navigateurs : ce n'est
pas une base fiable.

## Decision
Exposer le meme ingest en **WebSocket**, `GET /streams/{id}/broadcast/ws` :
chaque trame binaire est un chunk audio, diffuse tel quel par le hub de
streaming (ADR 003) aux auditeurs SSE et audio brut. Les trames texte sont
ignorees, une trame est plafonnee a 64 KiB.

- **Memes regles que le POST** : role `broadcaster`, proprietaire du flux, flux
  `live`. Les verifications sont partagees (`broadcastAllowed`), les refus
  arrivent a la poignee de main avec les memes codes.
- **Meme preuve de vie** : la connexion ouverte est le signal que le
  diffuseur est la ; fermee sans remplacement dans `BROADCAST_GRACE_PERIOD`,
  le direct est arrete comme par `POST /stop`.
- **Auth** : header `Bearer` ou `?token=`, comme le chat (ADR 009), pour la
  meme raison : un WebSocket navigateur ne peut pas poser de header.
- **Keepalive** ping/pong aux memes reglages que le chat ; toute trame audio
  repousse aussi le delai de lecture.
- **Le POST chunke reste servi** : il fait partie du contrat (`curl`, autres
  clients natifs), et l'enlever serait une rupture de compatibilite.
- **Un seul chemin cote Flutter** : `BroadcastNotifier` utilise le WebSocket
  sur mobile comme sur le web (`web_socket_channel`, deja present pour le
  chat). Le token est renouvele avant chaque (re)connexion par le
  `SessionRefresher`, et la console affiche l'etat reel de la connexion
  (`isConnected`) et non plus seulement celui de la capture micro.

## Justification
WebSocket est le seul transport qui envoie des trames au fil de l'eau depuis
tous les navigateurs, en HTTP/1.1 comme derriere le reverse proxy de
production (Caddy). L'ADR 003 ecartait WebSocket cote *auditeurs* pour le
fan-out massif unidirectionnel ; ce choix reste, la diffusion vers les
auditeurs ne change pas. Ici il n'y a qu'une connexion par live, cote
diffuseur, et l'alternative (une rafale de petits POST, un par chunk)
multiplierait les requetes, se heurterait au rate limiting et perdrait
l'ordre des chunks sans serialisation cote client.

Le mobile bascule aussi sur le WebSocket plutot que de garder deux transports :
un seul code, un seul test, et le meme comportement de reconnexion partout.

## Consequences
- Nouvelle operation `broadcastStreamWebSocket` dans `backend/api/openapi.yaml`,
  couverte par `TestOpenAPICoversEveryRoute`.
- Tests : unite du handler (fan-out des trames, refus a la poignee de main,
  arret automatique apres le delai de grace) et bout en bout a travers le
  routeur complet (`internal/transport/http/broadcast_ws_test.go`) ; cote
  Flutter, `broadcast_provider_test.dart` parle a un vrai serveur WebSocket
  local.
- Les metriques `stream_bytes_sent_total` et l'arret automatique des directs
  sans diffuseur couvrent les deux entrees.

---

## Summary (English)

ADR 003 chose a chunked `POST /streams/{id}/broadcast` for the broadcaster:
the request body *is* the audio stream. That works from the mobile app
(dart:io writes each chunk to the socket as it arrives) but not from the
broadcasters' web console: in a browser Dio goes through `XMLHttpRequest`,
which only takes a complete body, so the adapter buffers the whole stream in
memory and only calls `send()` when the stream closes, i.e. at the end of the
live. The server received nothing during the broadcast and listeners stayed
on "Connected - Waiting for audio..." while the console said "connected".
The bug only shows in production, where broadcasters use the web console.
Streaming request bodies via `fetch` (`duplex: 'half'`) need HTTP/2 or
HTTP/3 and are not available in every browser, so they are not a reliable
base.

The same ingest is therefore also exposed as a **WebSocket**,
`GET /streams/{id}/broadcast/ws`: every binary frame is one audio chunk,
fanned out unchanged by the streaming hub to SSE and raw-audio listeners;
text frames are ignored and frames are capped at 64 KiB. It keeps the POST's
rules (broadcaster role, stream owner, stream `live`, shared checks and
identical refusal codes at the handshake), the same liveness rule (a
connection closed without a replacement within `BROADCAST_GRACE_PERIOD`
stops the stream), the chat's authentication (`Bearer` header or `?token=`,
since browser WebSockets cannot set headers) and the chat's ping/pong
keepalive settings. The chunked POST stays served for other native clients.
Both Flutter clients now use the WebSocket through a single
`BroadcastNotifier` (`web_socket_channel`, already used by the chat), refresh
the token before every (re)connection through the `SessionRefresher`, and
the console shows the real connection state rather than only the microphone
capture. WebSocket is the only transport that ships frames as they are
produced from every browser, over HTTP/1.1 and through the production
reverse proxy; ADR 003's case against WebSocket concerned the listener-side
mass fan-out, which is unchanged. Consequences: a new
`broadcastStreamWebSocket` operation in the OpenAPI description (covered by
`TestOpenAPICoversEveryRoute`), handler unit tests plus an end-to-end test
through the full router, a Flutter test against a real local WebSocket
server, and metrics and auto-stop that cover both entry points.
