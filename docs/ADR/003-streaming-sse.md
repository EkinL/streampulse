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

## Consequences

### Positif
- Implementation simple et robuste
- Compatible avec l'infrastructure HTTP existante
- Scalable horizontalement (un Hub par instance, load balancer en amont)

### Negatif
- Limite a 6 connexions SSE par domaine en HTTP/1.1 (resolu avec HTTP/2)
- Les chunks audio sont encodes en base64 dans les events SSE (+33% overhead)
- Pas de communication bidirectionnelle native (si chat necessaire, ajouter WebSocket separement)
