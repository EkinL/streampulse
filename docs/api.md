# StreamPulse API Documentation

Base URL: `http://localhost:8080`

## Authentication

All authenticated endpoints require the header:
```
Authorization: Bearer <access_token>
```

## Response Format

### Success
```json
{
  "data": { ... },
  "meta": { "requestId": "uuid", "timestamp": "2026-04-10T12:00:00Z" }
}
```

### Error
```json
{
  "error": { "code": "ERROR_CODE", "message": "Human-readable message" },
  "meta": { "requestId": "uuid", "timestamp": "2026-04-10T12:00:00Z" }
}
```

### Paginated
```json
{
  "data": [ ... ],
  "meta": { "page": 1, "perPage": 20, "total": 150, "requestId": "uuid", "timestamp": "..." }
}
```

---

## Endpoints

### Health

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | No | Health check |

### Auth

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/register` | No | Register a new user |
| POST | `/auth/login` | No | Login and get tokens |
| POST | `/auth/refresh` | No | Refresh access token |

**POST /auth/register**
```json
{ "email": "user@example.com", "username": "user1", "password": "securepass" }
```

**POST /auth/login**
```json
{ "email": "user@example.com", "password": "securepass" }
```

**POST /auth/refresh**
```json
{ "refresh_token": "uuid-refresh-token" }
```

**Response (all auth endpoints):**
```json
{
  "data": {
    "access_token": "jwt...",
    "refresh_token": "uuid",
    "expires_at": "2026-04-10T12:15:00Z",
    "user": { "id": "uuid", "email": "...", "username": "...", "role": "user" }
  }
}
```

### Streams

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| GET | `/streams` | No | - | List all streams |
| GET | `/streams/:id` | No | - | Get stream details |
| POST | `/streams` | Yes | Broadcaster | Create a stream |
| GET | `/streams/:id/listen` | Yes | User | Listen to live stream (SSE) |
| POST | `/streams/:id/start` | Yes | Broadcaster (owner) | Start broadcasting |
| POST | `/streams/:id/stop` | Yes | Broadcaster (owner) | Stop broadcasting |

**POST /streams**
```json
{ "title": "My Stream", "description": "Live jazz", "format": "mp3" }
```

**GET /streams/:id/listen** - SSE endpoint, returns base64-encoded audio chunks:
```
data: <base64-audio-chunk>

data: <base64-audio-chunk>
```

### Playlists

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/playlists` | Yes | List my playlists |
| POST | `/playlists` | Yes | Create playlist |
| GET | `/playlists/:id` | Yes | Get playlist + tracks (private: owner only, 404 otherwise) |
| PUT | `/playlists/:id` | Yes | Update playlist (owner) |
| DELETE | `/playlists/:id` | Yes | Delete playlist (owner) |
| POST | `/playlists/:id/tracks` | Yes | Add track at the end of the queue (owner) |
| PUT | `/playlists/:id/tracks` | Yes | Reorder the queue (owner) |
| DELETE | `/playlists/:id/tracks/:trackId` | Yes | Remove track, positions are compacted (owner) |

**POST /playlists**
```json
{ "name": "Chill Vibes", "is_public": true }
```

**POST /playlists/:id/tracks**
```json
{ "title": "Song Name", "url": "https://example.com/song.mp3", "duration": 240 }
```

**PUT /playlists/:id/tracks** — queue logic: tracks are stored with a `position`
(0..n-1) that defines the play order. The client sends the **complete** list of
track ids in the desired order; positions are rewritten atomically in a single
transaction. Responds with the updated playlist. `400` on missing/duplicate/extra
ids, `403` if not the owner, `404` on unknown playlist or track.
```json
{ "track_ids": ["uuid-3", "uuid-1", "uuid-2"] }
```

### Admin

| Method | Path | Auth | Role | Description |
|--------|------|------|------|-------------|
| GET | `/admin/users` | Yes | Admin | List all users |
| PUT | `/admin/users/:id/role` | Yes | Admin | Update user role |

**PUT /admin/users/:id/role**
```json
{ "role": "broadcaster" }
```

### Metrics

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/metrics` | Yes (Admin) | Prometheus metrics |

Prometheus does not go through this route: it scrapes an internal listener on `METRICS_PORT` (default `9091`), which is only reachable inside the Docker network and is never published on the host.

## Roles

| Role | Level | Permissions |
|------|-------|-------------|
| anonymous | 0 | Public endpoints only |
| user | 1 | Listen, playlists, favorites |
| broadcaster | 2 | All user + create/manage streams |
| admin | 3 | All broadcaster + user management |

## Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| BAD_REQUEST | 400 | Invalid input |
| UNAUTHORIZED | 401 | Missing or invalid token |
| FORBIDDEN | 403 | Insufficient permissions |
| NOT_FOUND | 404 | Resource not found |
| CONFLICT | 409 | Resource already exists |
| RATE_LIMITED | 429 | Too many requests |
| INTERNAL_ERROR | 500 | Server error |
| STREAM_NOT_LIVE | 400 | Stream is not live |
