# ADR 003: SSE pour le Streaming Audio

## Statut
Accepted

## Contexte
StreamPulse doit diffuser de l'audio en temps reel d'un diffuseur vers N auditeurs. Deux approches principales : Server-Sent Events (SSE) et WebSocket.

## Decision
Utiliser **Server-Sent Events (SSE)** pour la diffusion audio du serveur vers les auditeurs.
Le diffuseur envoie les chunks audio via HTTP chunked transfer encoding (POST).

## Justification

### Pourquoi SSE plutot que WebSocket

1. **Unidirectionnel** : Le flux audio est naturellement unidirectionnel (serveur -> client). SSE est concu pour ce pattern.
2. **HTTP natif** : SSE fonctionne sur HTTP/1.1 standard, pas besoin de protocole specifique. Traverse facilement les proxies, load balancers et CDN.
3. **Reconnexion automatique** : Le navigateur/client SSE gere automatiquement la reconnexion avec `Last-Event-ID`.
4. **Simplicite** : Implementation cote serveur tres simple (flush HTTP). Pas de gestion de frames WebSocket.
5. **Compatible HTTP/2** : Multiplexage natif, pas de limite de connexions simultanees.

### Pourquoi pas WebSocket
- WebSocket est bidirectionnel, ce qui n'est pas necessaire pour l'ecoute audio
- Plus complexe a gerer (handshake, ping/pong, frames)
- Problemes courants avec les proxies et load balancers
- WebSocket pourrait etre utilise pour les fonctionnalites interactives futures (chat)

## Architecture de diffusion

```
Diffuseur --[POST chunked]--> Hub --[SSE]--> Auditeur 1
                                  --[SSE]--> Auditeur 2
                                  --[SSE]--> Auditeur N
```

Le Hub utilise un pattern fan-out avec goroutines et channels Go pour une distribution non-bloquante.

## Preuve de charge

Le Hub est couvert par des benchmarks et deux tests de charge, joues sous
`-race` a chaque `go test ./...` (`make load-test` pour les lancer seuls,
`make bench` pour les benchmarks).

| Preuve | Fichier | Ce qui est verifie |
|--------|---------|--------------------|
| `TestHubFanOutNListeners` | `internal/infrastructure/streaming/hub_test.go` | 1000 auditeurs (goroutine + channel chacun) recoivent l'integralite de 200 chunks de 4 KiB |
| `TestHubSlowListenerDoesNotBlockOthers` | idem | un auditeur qui ne lit plus ne bloque ni `Broadcast` ni les autres auditeurs (envoi non bloquant, perte locale) |
| `TestHubConcurrentChurn` | idem | connexions/deconnexions/broadcasts concurrents sur 3 flux, Hub vide a la fin (pas de fuite) |
| `TestStreamFanOutOverSSE` | `internal/transport/http/stream_load_test.go` | 500 vrais clients HTTP en SSE a travers le routeur complet (JWT, RBAC, rate-limit) : chaque octet recu dans l'ordre, puis Hub et gauge `active_listeners` a zero apres deconnexion |
| `BenchmarkHubBroadcast` | `hub_test.go` | cout d'un chunk de 4 KiB pour 10 / 100 / 1000 / 10000 auditeurs |

Mesures de reference (Apple M1 Pro, 8 coeurs, Go 1.26.7, `make bench`) :

| Auditeurs | Temps par chunk de 4 KiB | Cout par auditeur | Debit de fan-out |
|-----------|--------------------------|-------------------|------------------|
| 10 | 19 us | 1,9 us | 2,2 GB/s |
| 100 | 155 us | 1,6 us | 2,6 GB/s |
| 1 000 | 1,3 ms | 1,3 us | 3,2 GB/s |
| 10 000 | 18,4 ms | 1,8 us | 2,2 GB/s |

Connexion + deconnexion d'un auditeur sur un flux qui en compte 1000 : 1,5 us, 9 allocations.

Lecture : un flux MP3 a 128 kbit/s produit 4 chunks de 4 KiB par seconde. A
10 000 auditeurs, le Hub passe ~74 ms par seconde a diffuser, soit ~7 % d'un
coeur. Le cout est lineaire en N (une copie du chunk et un envoi sur channel
par auditeur), et la couche HTTP/SSE (encodage base64, ecriture socket) reste
parallele puisque chaque auditeur a sa goroutine. En pratique, la limite vient
donc de la bande passante sortante (10 000 x 128 kbit/s = 1,3 Gbit/s) et du
nombre de descripteurs de fichiers, pas du Hub.

Le test de bout en bout livre 125 MiB a 500 auditeurs en ~4,3 s sous `-race`
(le detecteur de course ralentit fortement ; sans lui, le goulot est le
loopback et non le Hub).

## Consequences

### Positif
- Implementation simple et robuste
- Compatible avec l'infrastructure HTTP existante
- Scalable horizontalement (un Hub par instance, load balancer en amont)

### Negatif
- Limite a 6 connexions SSE par domaine en HTTP/1.1 (resolu avec HTTP/2)
- Les chunks audio sont encodes en base64 dans les events SSE (+33% overhead)
- Pas de communication bidirectionnelle native (si chat necessaire, ajouter WebSocket separement)

---

## Summary (English)

Server-Sent Events, not WebSocket, carries the broadcaster-to-listener
audio fan-out: the stream is inherently one-directional, SSE runs over
plain HTTP/1.1 (traversing proxies and load balancers without a special
protocol), and the server-side implementation is a simple HTTP flush,
against WebSocket's added handshake, ping/pong and framing complexity.
The in-memory Hub fans chunks out to listeners via goroutines and
channels, non-blockingly. Benchmarks and two load tests (run under `-race`
on every `go test ./...`) back the design: cost per listener stays flat
from 10 to 10,000 (1.3-1.9us on an M1 Pro reference machine), a slow
listener never blocks the broadcaster or other listeners
(`TestHubSlowListenerDoesNotBlockOthers`), and 500 real HTTP/SSE clients
receive every byte in order end-to-end
(`TestStreamFanOutOverSSE`). The accepted trade-off is a 33% bandwidth
overhead from SSE's base64 event framing — addressed later by adding a
raw-audio endpoint (`/audio`) alongside `/listen` — and no native
bidirectional channel, which a future chat feature would need to add
separately via WebSocket.
