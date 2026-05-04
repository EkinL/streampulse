package postgres

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/streampulse/backend/internal/domain"
)

type FavoriteRepo struct {
	pool *pgxpool.Pool
}

func NewFavoriteRepo(pool *pgxpool.Pool) *FavoriteRepo {
	return &FavoriteRepo{pool: pool}
}

func (r *FavoriteRepo) Add(ctx context.Context, userID, streamID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO favorites (user_id, stream_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		userID, streamID,
	)
	if err != nil {
		return fmt.Errorf("favorite_repo: add: %w", err)
	}
	return nil
}

func (r *FavoriteRepo) Remove(ctx context.Context, userID, streamID uuid.UUID) error {
	result, err := r.pool.Exec(ctx,
		"DELETE FROM favorites WHERE user_id = $1 AND stream_id = $2", userID, streamID,
	)
	if err != nil {
		return fmt.Errorf("favorite_repo: remove: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("favorite_repo: remove: %w", domain.ErrNotFound)
	}
	return nil
}

func (r *FavoriteRepo) ListByUser(ctx context.Context, userID uuid.UUID, page, perPage int) ([]domain.Stream, int, error) {
	offset := (page - 1) * perPage

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM favorites WHERE user_id = $1", userID).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("favorite_repo: list count: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT s.id, s.title, s.description, s.owner_id, s.status, s.listener_count, s.format, s.created_at, s.updated_at
		 FROM streams s
		 INNER JOIN favorites f ON f.stream_id = s.id
		 WHERE f.user_id = $1
		 ORDER BY f.created_at DESC LIMIT $2 OFFSET $3`,
		userID, perPage, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("favorite_repo: list: %w", err)
	}
	defer rows.Close()

	var streams []domain.Stream
	for rows.Next() {
		var s domain.Stream
		var status string
		if err := rows.Scan(&s.ID, &s.Title, &s.Description, &s.OwnerID, &status,
			&s.ListenerCount, &s.Format, &s.CreatedAt, &s.UpdatedAt); err != nil {
			return nil, 0, fmt.Errorf("favorite_repo: list scan: %w", err)
		}
		s.Status = domain.StreamStatus(status)
		streams = append(streams, s)
	}
	return streams, total, nil
}

func (r *FavoriteRepo) Exists(ctx context.Context, userID, streamID uuid.UUID) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		"SELECT EXISTS(SELECT 1 FROM favorites WHERE user_id = $1 AND stream_id = $2)",
		userID, streamID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("favorite_repo: exists: %w", err)
	}
	return exists, nil
}
