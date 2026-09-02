# ADR 009: WebSocket pour le chat de live

## Statut
Accepted

## Contexte
Le sujet propose en bonus un chat en direct entre les auditeurs d'un meme
flux. L'ADR 003 a retenu SSE pour la diffusion audio *parce qu'elle est
unidirectionnelle*, et notait deja que « WebSocket pourrait etre utilise pour
les fonctionnalites interactives futures (chat) ». Le chat est ce cas : chaque
participant ecrit ET recoit.

## Decision
Un salon de chat ephemere par flux en direct, expose en **WebSocket** sur
`GET /streams/{id}/chat/ws` (gorilla/websocket cote serveur,
`web_socket_channel` cote Flutter).

- **Un salon par live** : il faut que le flux soit `live` pour entrer ; quand
  le diffuseur arrete le live, le salon est ferme et chaque participant recoit
  une trame de fermeture (`1001 going away`).
- **Ephemere** : salon et historique vivent en memoire dans un hub dedie
  (`internal/infrastructure/chat`), rien n'est persiste en base. Les
  50 derniers messages sont rejoues a l'arrivee d'un participant.
- **Identite cote serveur** : le client n'envoie que `{"text": "..."}`
  (500 caracteres max) ; auteur et horodatage viennent des claims du JWT,
  personne ne peut parler au nom d'un autre.
- **Auth** : header `Bearer` classique, ou `?token=` en secours — l'API
  WebSocket des navigateurs ne permet pas de poser de header sur la poignee
  de main. Pas de cookie, donc pas de surface CSRF : la verification
  d'Origin est volontairement desactivee.

## Justification

### Pourquoi WebSocket ici, alors que l'audio est en SSE
Les arguments de l'ADR 003 s'inversent point par point : le chat est
bidirectionnel (un POST par message + un canal SSE de retour feraient deux
connexions et deux chemins de code), le trafic est minuscule (pas d'enjeu de
debit, les soucis de proxy/buffering du WebSocket sont sans objet a cette
echelle), et le keepalive ping/pong integre detecte les participants partis
sans fermer proprement. Les deux ADR sont donc complementaires : SSE pour le
fan-out massif unidirectionnel, WebSocket pour l'interactif leger.

### Pourquoi reutiliser le pattern du hub de streaming
Le hub de chat reprend le fan-out goroutines + channels et reutilise
`streaming.Client` tel quel (un participant = un channel de sortie + un
signal de fermeture). Meme proprietes : envoi non bloquant, un participant
lent perd des messages mais ne bloque personne, et les tests de concurrence
tournent sous `-race`.

### Pourquoi ne rien persister
Le sujet demande un chat « entre auditeurs d'un meme flux » : la conversation
n'a pas de valeur apres le live, et ne pas la stocker evite une table, une
politique de retention RGPD et une moderation a posteriori. Si un replay
devenait necessaire, une table `chat_messages` s'ajouterait sans changer le
protocole.

## Consequences
- Nouvelles metriques metier : `chat_active_connections` (gauge) et
  `chat_messages_total` (compteur).
- L'operation est decrite dans `backend/api/openapi.yaml`
  (`streamChatWebSocket`, schema `ChatMessage`) ; le garde-fou
  `TestOpenAPICoversEveryRoute` la couvre comme les autres routes.
- Tests : unite du hub (`internal/infrastructure/chat/hub_test.go`) et bout
  en bout a travers le routeur complet, vrais clients WebSocket
  (`internal/transport/http/chat_ws_test.go`).

---

## Summary (English)

The subject offers a live chat between listeners of the same stream as a
bonus feature. [ADR 003](003-streaming-sse.md) chose SSE for audio
*because* the fan-out is unidirectional, and already flagged WebSocket as
the right tool for future interactive features. Chat is that case: every
participant both writes and receives. The two decisions are therefore
complementary rather than contradictory — SSE for one-way mass fan-out,
WebSocket for lightweight interaction — and ADR 003's arguments invert
point by point here: a POST per message plus a return SSE channel would
mean two connections and two code paths, chat traffic is tiny so the
proxy and buffering concerns that disqualified WebSocket for audio are
moot at this scale, and WebSocket's built-in ping/pong keepalive detects
participants who vanish without closing cleanly.

Each live stream gets one **ephemeral room**, exposed at
`GET /streams/{id}/chat/ws` (`gorilla/websocket` server-side,
`web_socket_channel` in Flutter). The stream must be `live` to enter; when
the broadcaster stops it, the room closes and every participant receives a
`1001 going away` close frame. Room and history live in memory in a
dedicated hub (`internal/infrastructure/chat`) and are never written to the
database — the last 50 messages are replayed to each arriving participant.
Identity is set server-side: the client only ever sends `{"text": "..."}`
(500 characters maximum), while author and timestamp come from the JWT
claims, so nobody can speak in someone else's name. Authentication accepts
the usual `Bearer` header or a `?token=` query fallback, because the
browser WebSocket API cannot set headers on the handshake; since no cookie
is involved there is no CSRF surface, so Origin checking is deliberately
disabled.

The chat hub reuses the streaming hub's goroutines-and-channels fan-out and
`streaming.Client` as-is, inheriting the same properties: non-blocking
sends, a slow participant loses messages but blocks nobody, and the
concurrency tests run under `-race`. Nothing is persisted because the
conversation has no value once the live ends, which also avoids a table, a
GDPR retention policy and after-the-fact moderation; should replay ever be
required, a `chat_messages` table would slot in without changing the
protocol. Consequences: two new business metrics
(`chat_active_connections` gauge, `chat_messages_total` counter), the
operation is described in `backend/api/openapi.yaml`
(`streamChatWebSocket`, `ChatMessage` schema) and guarded by
`TestOpenAPICoversEveryRoute` like every other route, and it is covered by
hub unit tests plus end-to-end tests driving real WebSocket clients through
the complete router.
