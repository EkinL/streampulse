package postgres

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/streampulse/backend/internal/domain"
)

type MusicFavoriteRepo struct {
	pool *pgxpool.Pool
}

func NewMusicFavoriteRepo(pool *pgxpool.Pool) *MusicFavoriteRepo {
	return &MusicFavoriteRepo{pool: pool}
}

func (r *MusicFavoriteRepo) Add(ctx context.Context, userID, musicID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO music_favorites (user_id, music_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		userID, musicID,
	)
	if err != nil {
		return fmt.Errorf("music_favorite_repo: add: %w", err)
	}
	return nil
}

func (r *MusicFavoriteRepo) Remove(ctx context.Context, userID, musicID uuid.UUID) error {
	result, err := r.pool.Exec(ctx,
		"DELETE FROM music_favorites WHERE user_id = $1 AND music_id = $2", userID, musicID,
	)
	if err != nil {
		return fmt.Errorf("music_favorite_repo: remove: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("music_favorite_repo: remove: %w", domain.ErrNotFound)
	}
	return nil
}

func (r *MusicFavoriteRepo) ListByUser(ctx context.Context, userID uuid.UUID, page, perPage int) ([]domain.Music, int, error) {
	offset := (page - 1) * perPage

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM music_favorites WHERE user_id = $1", userID).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("music_favorite_repo: list count: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT m.id, m.title, m.artist, m.album, m.duration, m.url, m.cover_url, m.uploaded_by, m.created_at
		 FROM music m
		 INNER JOIN music_favorites mf ON mf.music_id = m.id
		 WHERE mf.user_id = $1
		 ORDER BY mf.created_at DESC LIMIT $2 OFFSET $3`,
		userID, perPage, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("music_favorite_repo: list: %w", err)
	}
	defer rows.Close()

	tracks, err := scanMusicRows(rows)
	if err != nil {
		return nil, 0, fmt.Errorf("music_favorite_repo: list scan: %w", err)
	}
	return tracks, total, nil
}

func (r *MusicFavoriteRepo) Exists(ctx context.Context, userID, musicID uuid.UUID) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		"SELECT EXISTS(SELECT 1 FROM music_favorites WHERE user_id = $1 AND music_id = $2)",
		userID, musicID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("music_favorite_repo: exists: %w", err)
	}
	return exists, nil
}

func (r *MusicFavoriteRepo) ListIDs(ctx context.Context, userID uuid.UUID) ([]uuid.UUID, error) {
	rows, err := r.pool.Query(ctx,
		"SELECT music_id FROM music_favorites WHERE user_id = $1", userID,
	)
	if err != nil {
		return nil, fmt.Errorf("music_favorite_repo: list_ids: %w", err)
	}
	defer rows.Close()

	var ids []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("music_favorite_repo: list_ids scan: %w", err)
		}
		ids = append(ids, id)
	}
	return ids, nil
}
