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

type MusicRepo struct {
	pool *pgxpool.Pool
}

func NewMusicRepo(pool *pgxpool.Pool) *MusicRepo {
	return &MusicRepo{pool: pool}
}

func (r *MusicRepo) Create(ctx context.Context, music *domain.Music) error {
	now := time.Now().UTC()
	if music.ID == uuid.Nil {
		music.ID = uuid.New()
	}
	music.CreatedAt = now

	var coverURL *string
	if music.CoverURL != "" {
		coverURL = &music.CoverURL
	}

	_, err := r.pool.Exec(ctx,
		`INSERT INTO music (id, title, artist, album, duration, url, cover_url, uploaded_by, created_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		music.ID, music.Title, music.Artist, music.Album, music.Duration,
		music.URL, coverURL, music.UploadedBy, music.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("music_repo: create: %w", err)
	}
	return nil
}

func (r *MusicRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Music, error) {
	var m domain.Music
	var coverURL *string
	err := r.pool.QueryRow(ctx,
		`SELECT id, title, artist, album, duration, url, cover_url, uploaded_by, created_at
		 FROM music WHERE id = $1`, id,
	).Scan(&m.ID, &m.Title, &m.Artist, &m.Album, &m.Duration,
		&m.URL, &coverURL, &m.UploadedBy, &m.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("music_repo: find: %w", domain.ErrNotFound)
		}
		return nil, fmt.Errorf("music_repo: find: %w", err)
	}
	if coverURL != nil {
		m.CoverURL = *coverURL
	}
	return &m, nil
}

func (r *MusicRepo) List(ctx context.Context, page, perPage int) ([]domain.Music, int, error) {
	offset := (page - 1) * perPage

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM music").Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("music_repo: list count: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT id, title, artist, album, duration, url, cover_url, uploaded_by, created_at
		 FROM music ORDER BY created_at DESC LIMIT $1 OFFSET $2`, perPage, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("music_repo: list: %w", err)
	}
	defer rows.Close()

	tracks, err := scanMusicRows(rows)
	if err != nil {
		return nil, 0, err
	}
	return tracks, total, nil
}

func (r *MusicRepo) Search(ctx context.Context, query string, page, perPage int) ([]domain.Music, int, error) {
	offset := (page - 1) * perPage

	var total int
	if err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM music
		 WHERE to_tsvector('english', title || ' ' || artist) @@ plainto_tsquery('english', $1)`,
		query,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("music_repo: search count: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT id, title, artist, album, duration, url, cover_url, uploaded_by, created_at
		 FROM music
		 WHERE to_tsvector('english', title || ' ' || artist) @@ plainto_tsquery('english', $1)
		 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
		query, perPage, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("music_repo: search: %w", err)
	}
	defer rows.Close()

	tracks, err := scanMusicRows(rows)
	if err != nil {
		return nil, 0, err
	}
	return tracks, total, nil
}

func (r *MusicRepo) ListByUploader(ctx context.Context, uploaderID uuid.UUID, page, perPage int) ([]domain.Music, int, error) {
	offset := (page - 1) * perPage

	var total int
	if err := r.pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM music WHERE uploaded_by = $1", uploaderID,
	).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("music_repo: list_by_uploader count: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT id, title, artist, album, duration, url, cover_url, uploaded_by, created_at
		 FROM music WHERE uploaded_by = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
		uploaderID, perPage, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("music_repo: list_by_uploader: %w", err)
	}
	defer rows.Close()

	tracks, err := scanMusicRows(rows)
	if err != nil {
		return nil, 0, err
	}
	return tracks, total, nil
}

func (r *MusicRepo) AllByUploader(ctx context.Context, uploaderID uuid.UUID) ([]domain.Music, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, title, artist, album, duration, url, cover_url, uploaded_by, created_at
		 FROM music WHERE uploaded_by = $1`,
		uploaderID,
	)
	if err != nil {
		return nil, fmt.Errorf("music_repo: all_by_uploader: %w", err)
	}
	defer rows.Close()

	tracks, err := scanMusicRows(rows)
	if err != nil {
		return nil, err
	}
	return tracks, nil
}

func (r *MusicRepo) Update(ctx context.Context, music *domain.Music) error {
	var coverURL *string
	if music.CoverURL != "" {
		coverURL = &music.CoverURL
	}

	result, err := r.pool.Exec(ctx,
		"UPDATE music SET title = $1, artist = $2, album = $3, cover_url = $4 WHERE id = $5",
		music.Title, music.Artist, music.Album, coverURL, music.ID,
	)
	if err != nil {
		return fmt.Errorf("music_repo: update: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("music_repo: update: %w", domain.ErrNotFound)
	}
	return nil
}

func (r *MusicRepo) Delete(ctx context.Context, id uuid.UUID) error {
	result, err := r.pool.Exec(ctx, "DELETE FROM music WHERE id = $1", id)
	if err != nil {
		return fmt.Errorf("music_repo: delete: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("music_repo: delete: %w", domain.ErrNotFound)
	}
	return nil
}

func scanMusicRows(rows pgx.Rows) ([]domain.Music, error) {
	var tracks []domain.Music
	for rows.Next() {
		var m domain.Music
		var coverURL *string
		if err := rows.Scan(&m.ID, &m.Title, &m.Artist, &m.Album, &m.Duration,
			&m.URL, &coverURL, &m.UploadedBy, &m.CreatedAt); err != nil {
			return nil, fmt.Errorf("music_repo: scan: %w", err)
		}
		if coverURL != nil {
			m.CoverURL = *coverURL
		}
		tracks = append(tracks, m)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("music_repo: scan: %w", err)
	}
	return tracks, nil
}
