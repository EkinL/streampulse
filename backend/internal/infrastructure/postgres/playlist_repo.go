package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/streampulse/backend/internal/domain"
)

type PlaylistRepo struct {
	pool *pgxpool.Pool
}

func NewPlaylistRepo(pool *pgxpool.Pool) *PlaylistRepo {
	return &PlaylistRepo{pool: pool}
}

func (r *PlaylistRepo) Create(ctx context.Context, playlist *domain.Playlist) error {
	now := time.Now().UTC()
	if playlist.ID == uuid.Nil {
		playlist.ID = uuid.New()
	}
	playlist.CreatedAt = now
	playlist.UpdatedAt = now

	_, err := r.pool.Exec(ctx,
		`INSERT INTO playlists (id, name, owner_id, is_public, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		playlist.ID, playlist.Name, playlist.OwnerID, playlist.IsPublic, playlist.CreatedAt, playlist.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("playlist_repo: create: %w", err)
	}
	return nil
}

func (r *PlaylistRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Playlist, error) {
	var p domain.Playlist
	err := r.pool.QueryRow(ctx,
		`SELECT id, name, owner_id, is_public, created_at, updated_at FROM playlists WHERE id = $1`, id,
	).Scan(&p.ID, &p.Name, &p.OwnerID, &p.IsPublic, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("playlist_repo: find: %w", domain.ErrNotFound)
		}
		return nil, fmt.Errorf("playlist_repo: find: %w", err)
	}

	tracks, err := r.loadTracks(ctx, id)
	if err != nil {
		return nil, err
	}
	p.Tracks = tracks
	p.TrackCount = len(tracks)
	return &p, nil
}

func (r *PlaylistRepo) ListByOwner(ctx context.Context, ownerID uuid.UUID, page, perPage int) ([]domain.Playlist, int, error) {
	offset := (page - 1) * perPage

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM playlists WHERE owner_id = $1", ownerID).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("playlist_repo: list_by_owner count: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT p.id, p.name, p.owner_id, p.is_public, p.created_at, p.updated_at,
		        (SELECT COUNT(*) FROM tracks t WHERE t.playlist_id = p.id) AS track_count
		 FROM playlists p WHERE p.owner_id = $1 ORDER BY p.created_at DESC LIMIT $2 OFFSET $3`,
		ownerID, perPage, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("playlist_repo: list_by_owner: %w", err)
	}
	defer rows.Close()

	return r.scanPlaylists(rows, total)
}

func (r *PlaylistRepo) ListPublic(ctx context.Context, page, perPage int) ([]domain.Playlist, int, error) {
	offset := (page - 1) * perPage

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM playlists WHERE is_public = true").Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("playlist_repo: list_public count: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT p.id, p.name, p.owner_id, p.is_public, p.created_at, p.updated_at,
		        (SELECT COUNT(*) FROM tracks t WHERE t.playlist_id = p.id) AS track_count
		 FROM playlists p WHERE p.is_public = true ORDER BY p.created_at DESC LIMIT $1 OFFSET $2`,
		perPage, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("playlist_repo: list_public: %w", err)
	}
	defer rows.Close()

	return r.scanPlaylists(rows, total)
}

func (r *PlaylistRepo) Update(ctx context.Context, playlist *domain.Playlist) error {
	playlist.UpdatedAt = time.Now().UTC()
	result, err := r.pool.Exec(ctx,
		`UPDATE playlists SET name = $1, is_public = $2, updated_at = $3 WHERE id = $4`,
		playlist.Name, playlist.IsPublic, playlist.UpdatedAt, playlist.ID,
	)
	if err != nil {
		return fmt.Errorf("playlist_repo: update: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("playlist_repo: update: %w", domain.ErrNotFound)
	}
	return nil
}

func (r *PlaylistRepo) Delete(ctx context.Context, id uuid.UUID) error {
	result, err := r.pool.Exec(ctx, "DELETE FROM playlists WHERE id = $1", id)
	if err != nil {
		return fmt.Errorf("playlist_repo: delete: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("playlist_repo: delete: %w", domain.ErrNotFound)
	}
	return nil
}

func (r *PlaylistRepo) AddTrack(ctx context.Context, playlistID uuid.UUID, track *domain.Track) error {
	if track.ID == uuid.Nil {
		track.ID = uuid.New()
	}

	var maxPos int
	err := r.pool.QueryRow(ctx,
		"SELECT COALESCE(MAX(position), -1) FROM tracks WHERE playlist_id = $1", playlistID,
	).Scan(&maxPos)
	if err != nil {
		return fmt.Errorf("playlist_repo: add_track max_pos: %w", err)
	}
	track.Position = maxPos + 1

	_, err = r.pool.Exec(ctx,
		`INSERT INTO tracks (id, playlist_id, title, url, duration, position)
		 VALUES ($1, $2, $3, $4, $5, $6)`,
		track.ID, playlistID, track.Title, track.URL, track.Duration, track.Position,
	)
	if err != nil {
		return fmt.Errorf("playlist_repo: add_track: %w", err)
	}
	return nil
}

func (r *PlaylistRepo) RemoveTrack(ctx context.Context, playlistID, trackID uuid.UUID) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("playlist_repo: remove_track: begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// RETURNING gives us the freed position so the tracks after it can slide up.
	var removedPos int
	err = tx.QueryRow(ctx,
		"DELETE FROM tracks WHERE id = $1 AND playlist_id = $2 RETURNING position",
		trackID, playlistID,
	).Scan(&removedPos)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return fmt.Errorf("playlist_repo: remove_track: %w", domain.ErrNotFound)
		}
		return fmt.Errorf("playlist_repo: remove_track: %w", err)
	}

	// Compact positions so the queue stays gapless (0..n-1).
	_, err = tx.Exec(ctx,
		"UPDATE tracks SET position = position - 1 WHERE playlist_id = $1 AND position > $2",
		playlistID, removedPos,
	)
	if err != nil {
		return fmt.Errorf("playlist_repo: remove_track: compact: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("playlist_repo: remove_track: commit: %w", err)
	}
	return nil
}

func (r *PlaylistRepo) ReorderTracks(ctx context.Context, playlistID uuid.UUID, trackIDs []uuid.UUID) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("playlist_repo: reorder_tracks: begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// The new order must cover the playlist exactly: same track count,
	// and every id must belong to the playlist (checked per UPDATE below).
	var count int
	if err := tx.QueryRow(ctx,
		"SELECT COUNT(*) FROM tracks WHERE playlist_id = $1", playlistID,
	).Scan(&count); err != nil {
		return fmt.Errorf("playlist_repo: reorder_tracks: count: %w", err)
	}
	if count != len(trackIDs) {
		return fmt.Errorf("playlist_repo: reorder_tracks: expected %d track ids, got %d: %w",
			count, len(trackIDs), domain.ErrInvalidInput)
	}

	for pos, trackID := range trackIDs {
		result, err := tx.Exec(ctx,
			"UPDATE tracks SET position = $1 WHERE id = $2 AND playlist_id = $3",
			pos, trackID, playlistID,
		)
		if err != nil {
			return fmt.Errorf("playlist_repo: reorder_tracks: %w", err)
		}
		if result.RowsAffected() == 0 {
			return fmt.Errorf("playlist_repo: reorder_tracks: track %s: %w", trackID, domain.ErrNotFound)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("playlist_repo: reorder_tracks: commit: %w", err)
	}
	return nil
}

func (r *PlaylistRepo) loadTracks(ctx context.Context, playlistID uuid.UUID) ([]domain.Track, error) {
	rows, err := r.pool.Query(ctx,
		"SELECT id, title, url, duration, position FROM tracks WHERE playlist_id = $1 ORDER BY position",
		playlistID,
	)
	if err != nil {
		return nil, fmt.Errorf("playlist_repo: load_tracks: %w", err)
	}
	defer rows.Close()

	var tracks []domain.Track
	for rows.Next() {
		var t domain.Track
		if err := rows.Scan(&t.ID, &t.Title, &t.URL, &t.Duration, &t.Position); err != nil {
			return nil, fmt.Errorf("playlist_repo: load_tracks scan: %w", err)
		}
		tracks = append(tracks, t)
	}
	return tracks, nil
}

func (r *PlaylistRepo) scanPlaylists(rows pgx.Rows, total int) ([]domain.Playlist, int, error) {
	var playlists []domain.Playlist
	for rows.Next() {
		var p domain.Playlist
		if err := rows.Scan(&p.ID, &p.Name, &p.OwnerID, &p.IsPublic, &p.CreatedAt, &p.UpdatedAt, &p.TrackCount); err != nil {
			return nil, 0, fmt.Errorf("playlist_repo: scan: %w", err)
		}
		playlists = append(playlists, p)
	}
	return playlists, total, nil
}
