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

## Roles

Roles are ordered. An endpoint that requires `broadcaster` is therefore also
reachable by an `admin`.

| Role | Level | Permissions |
|------|-------|-------------|
| anonymous | 0 | Public endpoints only: browse streams and music, search |
| user | 1 | + listen, favorites, playlists, own account (`/users/me`) |
| broadcaster | 2 | + create and run streams, upload music |
| admin | 3 | + user management (roles, deletion), `/metrics` |

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

Because these connections are long-lived, `ReadTimeout` and `WriteTimeout` are
set to `0` on the HTTP server — see `cmd/server/main.go`. Note that this is the
*main* server, so the timeouts are disabled for every route, not just the
streaming ones. The rationale for SSE over WebSocket is in
[ADR 003](ADR/003-streaming-sse.md).

## Metrics

`GET /metrics` is restricted to `admin`. Prometheus does not use it: it scrapes
an internal listener on `METRICS_PORT` (default `9091`), reachable only from
inside the Docker network and never published on the host.
