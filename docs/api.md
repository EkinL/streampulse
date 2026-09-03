# StreamPulse API

The **normative** description of this API is the OpenAPI 3.1 document
[`backend/api/openapi.yaml`](../backend/api/openapi.yaml). It is the single
source of truth: every route, parameter, payload, status code and error code is
specified there, and a Go test fails the build if the router and the document
ever disagree.

This page is the narrative companion — conventions, the auth flow, and how to
get a token in under a minute. It deliberately does **not** repeat the endpoint
reference, so it cannot drift from it.

| Where | What |
|-------|------|
| `backend/api/openapi.yaml` | The description, in the repository. |
| `GET /openapi.yaml` | The same document, embedded in the running binary. |
| `GET /docs` | Swagger UI, rendering the above. Needs internet for the renderer. |
| `make openapi-lint` | Validates the description (Redocly, also run in CI). |
| `go test ./internal/transport/http/` | Validates it against the real router. |

Base URL in local development: `http://localhost:8080` (`make up`).

## Conventions

Every response produced by a handler is wrapped in the same envelope.

**Success**
```json
{
  "data": { },
  "meta": { "requestId": "uuid", "timestamp": "2026-08-27T12:00:00Z" }
}
```

**Paginated** — list endpoints take `?page=` (default 1) and `?per_page=`
(default 20) and add three fields to `meta`:
```json
{
  "data": [],
  "meta": { "page": 1, "perPage": 20, "total": 150, "requestId": "uuid", "timestamp": "..." }
}
```

**Error**
```json
{
  "error": { "code": "ERROR_CODE", "message": "Human-readable message" },
  "meta": { "requestId": "uuid", "timestamp": "..." }
}
```

`meta.requestId` is generated per response and is the key to correlate a
client-side bug report with the structured logs and the OTEL trace.

> **Known inconsistency.** `401`, `403` and `429` raised by the middleware
> chain (authentication, RBAC, rate limiting) are written with `http.Error`:
> the body is the `error` object alone, without the `meta` envelope, and the
> `Content-Type` is `text/plain; charset=utf-8`. Errors raised inside a handler
> always use the JSON envelope above. Both shapes are documented on each
> operation in `openapi.yaml`.

## Authentication

Access tokens are JWT HS256, valid 15 minutes by default (`JWT_EXPIRY`).
Refresh tokens are opaque, **single use**, valid 168 h (`JWT_REFRESH_EXPIRY`):
`POST /auth/refresh` consumes the one you present and returns a new pair, so
replaying a refresh token returns `401`.

```
Authorization: Bearer <access_token>
```

Social login: `POST /auth/oauth` takes `{"provider": "google"|"apple",
"id_token": "..."}` — the ID token produced by Google Sign-In or Sign in with
Apple on the device. The server verifies it against the provider's public
JWKS and returns the same token pair as `/auth/login`, creating the account
on first sign-in. Providers are enabled by listing their OAuth client IDs in
`GOOGLE_OAUTH_CLIENT_IDS` / `APPLE_OAUTH_CLIENT_IDS` (otherwise `503`); setup
guide in `docs/social-login.md`.

### Quickstart

```bash
# 1. Create an account — the response already contains a usable token pair
curl -s -X POST http://localhost:8080/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"ada@streampulse.local","username":"ada","password":"correct-horse-battery-staple"}'

# 2. Keep the access token
TOKEN=$(curl -s -X POST http://localhost:8080/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"ada@streampulse.local","password":"correct-horse-battery-staple"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["access_token"])')

# 3. Call an authenticated endpoint
curl -s http://localhost:8080/playlists -H "Authorization: Bearer $TOKEN"
```

Prometheus does not go through this route: it scrapes an internal listener on `METRICS_PORT` (default `9091`), which is only reachable inside the Docker network and is never published on the host.

## Roles

Roles are ordered. An endpoint that requires `broadcaster` is therefore also
reachable by an `admin`.

| Role | Level | Permissions |
|------|-------|-------------|
| anonymous | 0 | No token: `GET /streams`, `GET /streams/{id}`, `GET /music*`, `GET /search` only |
| user | 1 | + listen, favorites, playlists, `GET /playlists/public`, own account (`/users/me`) |
| broadcaster | 2 | + create and run streams, upload music |
| admin | 3 | + user management (roles, deletion), `/metrics` |

> **This is the API contract, not the shipped clients.** Neither the
> mobile app nor the web console exposes a no-account mode: their router
> sends any unauthenticated screen straight to login. The four
> `anonymous`-level routes above only matter to a third party integrating
> the REST API directly. Note that despite its name, `GET /playlists/public`
> is **not** one of them — it requires a token; "public" there means
> visible to other logged-in users, not reachable without an account.

## Account and personal data

Any authenticated account, whatever its role, can read and erase its own
data — the two GDPR rights the API exposes directly
(see [rgpd.md](rgpd.md)):

- `GET /users/me` — everything held on the account, read from the database,
  never the password hash. This JSON is the data export.
- `DELETE /users/me` — erases the account and, by cascade, its refresh
  tokens, streams, playlists, favorites and uploaded tracks. Irreversible.
  The access token you still hold stays cryptographically valid until it
  expires (15 minutes) but `GET /users/me` now answers `404`, the refresh
  token is gone, and the email can be registered again.
- `DELETE /admin/users/{id}` — same effect, performed by an admin for a
  request received outside the app.

```bash
curl -s http://localhost:8080/users/me -H "Authorization: Bearer $TOKEN"
curl -s -X DELETE http://localhost:8080/users/me -H "Authorization: Bearer $TOKEN"
# {"data":{"status":"deleted"},"meta":{...}}
```

## Error codes

| Code | HTTP | Meaning |
|------|------|---------|
| `BAD_REQUEST` | 400 | Malformed body. Unknown JSON fields are rejected. |
| `INVALID_ID` | 400 | A path parameter is not a valid UUID (music routes). |
| `INVALID_BODY` | 400 | Unparseable multipart form, or missing `file` field. |
| `INVALID_INPUT` | 400 | Value rejected by a domain rule. |
| `STREAM_NOT_LIVE` | 400 | The stream is not broadcasting. |
| `UNAUTHORIZED` | 401 | Missing, malformed or expired token; bad credentials. |
| `FORBIDDEN` | 403 | Role too low, or not the owner of the resource. |
| `NOT_FOUND` | 404 | No such resource — also returned for a private playlist you do not own, so that a `403` cannot confirm the id exists. |
| `CONFLICT` | 409 | Email already registered, or stream already live. |
| `RATE_LIMITED` | 429 | Per-IP token bucket exhausted (`RATE_LIMIT_RPS`, burst `RATE_LIMIT_BURST`). |
| `INTERNAL_ERROR` | 500 | Unexpected server-side failure. |

## Streaming

Two ways to consume the same fan-out, both requiring authentication and a
`live` stream:

- `GET /streams/{id}/listen` — Server-Sent Events. First frame is an
  `event: connected` control frame, then one **base64-encoded** audio chunk per
  `data:` frame. For clients that can only speak SSE.
- `GET /streams/{id}/audio` — the raw audio byte stream, chunked, no framing.
  This is what the mobile player uses.

A broadcaster pushes audio with a single long-lived
`POST /streams/{id}/broadcast`: the body is read in 4 KiB chunks and each chunk
is fanned out to every connected listener. The stream must have been started
with `POST /streams/{id}/start` first.

The same ingest is also exposed as a **WebSocket**, `GET /streams/{id}/broadcast/ws`
(every binary frame is one chunk, text frames are ignored, frames are capped at
64 KiB, `?token=` accepted like the chat). This is what both Flutter clients
use: a browser cannot stream a request body (XMLHttpRequest buffers it until
the upload ends), so the chunked POST only ever worked from native clients.
Both entry points share the checks (owner, stream `live`) and the liveness
rule below (see [ADR 010](ADR/010-broadcast-websocket.md)).

`ReadTimeout` and `WriteTimeout` are enabled by default (30s) on every route
to bound slow or malicious clients. These three streaming handlers are the
only exception: each lifts the deadline **for its own connection only**, via
`http.NewResponseController` (see [ADR 005 - HTTP timeouts](ADR/005-http-timeouts.md)),
so a long broadcast never times out without disabling protection everywhere
else. The rationale for SSE over WebSocket is in
[ADR 003](ADR/003-streaming-sse.md).

## Live chat

Every live stream has one ephemeral chat room, open to the people in the
live. `GET /streams/{id}/chat/ws` upgrades the connection to a **WebSocket**
(this is the one bidirectional endpoint of the API — rationale in
[ADR 009](ADR/009-chat-websocket.md)):

- authentication: standard `Bearer` header, or `?token=` as a fallback for
  browsers (their WebSocket handshake cannot carry headers);
- the stream must be `live`; when the broadcaster stops it, the room closes
  and every participant receives a close frame (`1001`, "stream ended");
- the client only ever sends `{"text": "..."}` (≤ 500 characters); author and
  timestamp are set server-side from the token, so nobody can speak in
  someone else's name;
- every server frame is one JSON `ChatMessage` (`type` = `message`,
  `user_joined` or `user_left`); on join, the last 50 messages are replayed.

Nothing is persisted: the room and its history live in memory and die with
the live.

## Metrics

`GET /metrics` is restricted to `admin`. Prometheus does not use it: it scrapes
an internal listener on `METRICS_PORT` (default `9091`), reachable only from
inside the Docker network and never published on the host.

---

## Resume (francais)

Cette page reste volontairement en anglais, comme le veut l'usage du metier
pour une reference d'API — c'est cette page-la, pas le reste de la
documentation, qui a le plus de chances d'etre lue par un developpeur non
francophone. Elle ne repete pas la reference des routes, deja normative
dans [`backend/api/openapi.yaml`](../backend/api/openapi.yaml) (servie sur
`GET /openapi.yaml`, visualisee sur `GET /docs`).

**Ce qu'il faut retenir** : chaque reponse est enveloppee dans `{data,
meta}` (succes), `{data: [], meta: {page, perPage, total, ...}}` (listes
paginees) ou `{error: {code, message}, meta}` (erreurs) — sauf les 401/403/429
leves par les middlewares (auth, RBAC, rate limiting), qui repondent en
texte brut sans enveloppe `meta`, une incoherence connue et documentee sur
chaque operation concernee. L'authentification suit
[ADR 006](ADR/006-strategie-auth-jwt.md) : jeton d'acces JWT de 15 minutes,
refresh token opaque a usage unique de 168 h. Les roles sont hierarchises
(`user < broadcaster < admin`), chacun heritant des droits du precedent ;
`anonymous` designe simplement l'absence de jeton et ne couvre, cote API,
que `GET /streams`, `GET /music*` et `GET /search` — une capacite de
l'API, pas de l'application livree, qui exige un compte pour tout.
`GET /users/me` et `DELETE /users/me` exposent
directement les droits RGPD d'acces et d'effacement (detail dans
[rgpd.md](rgpd.md)). Le streaming se consomme par SSE (`/listen`, chunks
encodes en base64) ou par flux audio brut (`/audio`, ce que consomme
l'application mobile) ; les deux exigent un flux `live` et une
authentification. Chaque live a son salon de chat ephemere en WebSocket
(`/streams/{id}/chat/ws`, [ADR 009](ADR/009-chat-websocket.md)) : messages
limites a 500 caracteres, identite posee cote serveur depuis le jeton,
historique des 50 derniers messages rejoue a l'arrivee, salon ferme avec le
live, rien n'est persiste. `/metrics` est reserve au role `admin` et
Prometheus ne l'utilise pas — il scrute un listener interne separe, jamais
publie.
