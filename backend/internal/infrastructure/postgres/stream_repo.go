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

type StreamRepo struct {
	pool *pgxpool.Pool
}

func NewStreamRepo(pool *pgxpool.Pool) *StreamRepo {
	return &StreamRepo{pool: pool}
}

func (r *StreamRepo) Create(ctx context.Context, stream *domain.Stream) error {
	now := time.Now().UTC()
	if stream.ID == uuid.Nil {
		stream.ID = uuid.New()
	}
	stream.CreatedAt = now
	stream.UpdatedAt = now
	stream.Status = domain.StreamStatusIdle

	_, err := r.pool.Exec(ctx,
		`INSERT INTO streams (id, title, description, owner_id, status, listener_count, format, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		stream.ID, stream.Title, stream.Description, stream.OwnerID,
		string(stream.Status), stream.ListenerCount, stream.Format, stream.CreatedAt, stream.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("stream_repo: create: %w", err)
	}
	return nil
}

func (r *StreamRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Stream, error) {
	var s domain.Stream
	var status string
	err := r.pool.QueryRow(ctx,
		`SELECT id, title, description, owner_id, status, listener_count, format, created_at, updated_at
		 FROM streams WHERE id = $1`, id,
	).Scan(&s.ID, &s.Title, &s.Description, &s.OwnerID, &status,
		&s.ListenerCount, &s.Format, &s.CreatedAt, &s.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("stream_repo: find: %w", domain.ErrNotFound)
		}
		return nil, fmt.Errorf("stream_repo: find: %w", err)
	}
	s.Status = domain.StreamStatus(status)
	return &s, nil
}

func (r *StreamRepo) List(ctx context.Context, page, perPage int) ([]domain.Stream, int, error) {
	offset := (page - 1) * perPage

	var total int
	if err := r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM streams").Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("stream_repo: list count: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT id, title, description, owner_id, status, listener_count, format, created_at, updated_at
		 FROM streams ORDER BY created_at DESC LIMIT $1 OFFSET $2`, perPage, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("stream_repo: list: %w", err)
	}
	defer rows.Close()

	var streams []domain.Stream
	for rows.Next() {
		var s domain.Stream
		var status string
		if err := rows.Scan(&s.ID, &s.Title, &s.Description, &s.OwnerID, &status,
			&s.ListenerCount, &s.Format, &s.CreatedAt, &s.UpdatedAt); err != nil {
			return nil, 0, fmt.Errorf("stream_repo: list scan: %w", err)
		}
		s.Status = domain.StreamStatus(status)
		streams = append(streams, s)
	}
	return streams, total, nil
}

func (r *StreamRepo) UpdateStatus(ctx context.Context, id uuid.UUID, status domain.StreamStatus) error {
	result, err := r.pool.Exec(ctx,
		"UPDATE streams SET status = $1, updated_at = $2 WHERE id = $3",
		string(status), time.Now().UTC(), id,
	)
	if err != nil {
		return fmt.Errorf("stream_repo: update_status: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("stream_repo: update_status: %w", domain.ErrNotFound)
	}
	return nil
}

func (r *StreamRepo) UpdateListenerCount(ctx context.Context, id uuid.UUID, count int) error {
	_, err := r.pool.Exec(ctx,
		"UPDATE streams SET listener_count = $1, updated_at = $2 WHERE id = $3",
		count, time.Now().UTC(), id,
	)
	if err != nil {
		return fmt.Errorf("stream_repo: update_listener_count: %w", err)
	}
	return nil
}

func (r *StreamRepo) Update(ctx context.Context, stream *domain.Stream) error {
	stream.UpdatedAt = time.Now().UTC()
	result, err := r.pool.Exec(ctx,
		"UPDATE streams SET title = $1, description = $2, updated_at = $3 WHERE id = $4",
		stream.Title, stream.Description, stream.UpdatedAt, stream.ID,
	)
	if err != nil {
		return fmt.Errorf("stream_repo: update: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("stream_repo: update: %w", domain.ErrNotFound)
	}
	return nil
}

func (r *StreamRepo) Delete(ctx context.Context, id uuid.UUID) error {
	result, err := r.pool.Exec(ctx, "DELETE FROM streams WHERE id = $1", id)
	if err != nil {
		return fmt.Errorf("stream_repo: delete: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("stream_repo: delete: %w", domain.ErrNotFound)
	}
	return nil
}

func (r *StreamRepo) ListByOwner(ctx context.Context, ownerID uuid.UUID) ([]domain.Stream, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, title, description, owner_id, status, listener_count, format, created_at, updated_at
		 FROM streams WHERE owner_id = $1 ORDER BY created_at DESC`, ownerID,
	)
	if err != nil {
		return nil, fmt.Errorf("stream_repo: list_by_owner: %w", err)
	}
	defer rows.Close()

	var streams []domain.Stream
	for rows.Next() {
		var s domain.Stream
		var status string
		if err := rows.Scan(&s.ID, &s.Title, &s.Description, &s.OwnerID, &status,
			&s.ListenerCount, &s.Format, &s.CreatedAt, &s.UpdatedAt); err != nil {
			return nil, fmt.Errorf("stream_repo: list_by_owner scan: %w", err)
		}
		s.Status = domain.StreamStatus(status)
		streams = append(streams, s)
	}
	return streams, nil
}
