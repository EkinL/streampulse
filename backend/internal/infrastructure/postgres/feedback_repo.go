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

type FeedbackRepo struct {
	pool *pgxpool.Pool
}

func NewFeedbackRepo(pool *pgxpool.Pool) *FeedbackRepo {
	return &FeedbackRepo{pool: pool}
}

func (r *FeedbackRepo) Create(ctx context.Context, feedback *domain.Feedback) error {
	now := time.Now().UTC()
	if feedback.ID == uuid.Nil {
		feedback.ID = uuid.New()
	}
	feedback.Status = domain.FeedbackStatusNew
	feedback.CreatedAt = now
	feedback.UpdatedAt = now

	_, err := r.pool.Exec(ctx,
		`INSERT INTO feedback (id, user_id, type, message, app_version, platform, status, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		feedback.ID, feedback.UserID, feedback.Type, feedback.Message,
		feedback.AppVersion, feedback.Platform, feedback.Status, feedback.CreatedAt, feedback.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("feedback_repo: create: %w", err)
	}
	return nil
}

func (r *FeedbackRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Feedback, error) {
	var f domain.Feedback
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, type, message, app_version, platform, status, created_at, updated_at
		 FROM feedback WHERE id = $1`, id,
	).Scan(&f.ID, &f.UserID, &f.Type, &f.Message, &f.AppVersion, &f.Platform, &f.Status, &f.CreatedAt, &f.UpdatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("feedback_repo: find: %w", domain.ErrNotFound)
		}
		return nil, fmt.Errorf("feedback_repo: find: %w", err)
	}
	return &f, nil
}

func (r *FeedbackRepo) List(ctx context.Context, status domain.FeedbackStatus, page, perPage int) ([]domain.Feedback, int, error) {
	offset := (page - 1) * perPage

	var total int
	var countErr error
	if status == "" {
		countErr = r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM feedback").Scan(&total)
	} else {
		countErr = r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM feedback WHERE status = $1", status).Scan(&total)
	}
	if countErr != nil {
		return nil, 0, fmt.Errorf("feedback_repo: list count: %w", countErr)
	}

	var rows pgx.Rows
	var err error
	if status == "" {
		rows, err = r.pool.Query(ctx,
			`SELECT id, user_id, type, message, app_version, platform, status, created_at, updated_at
			 FROM feedback ORDER BY created_at DESC LIMIT $1 OFFSET $2`,
			perPage, offset,
		)
	} else {
		rows, err = r.pool.Query(ctx,
			`SELECT id, user_id, type, message, app_version, platform, status, created_at, updated_at
			 FROM feedback WHERE status = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
			status, perPage, offset,
		)
	}
	if err != nil {
		return nil, 0, fmt.Errorf("feedback_repo: list: %w", err)
	}
	defer rows.Close()

	var items []domain.Feedback
	for rows.Next() {
		var f domain.Feedback
		if err := rows.Scan(&f.ID, &f.UserID, &f.Type, &f.Message, &f.AppVersion, &f.Platform, &f.Status, &f.CreatedAt, &f.UpdatedAt); err != nil {
			return nil, 0, fmt.Errorf("feedback_repo: list scan: %w", err)
		}
		items = append(items, f)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("feedback_repo: list: %w", err)
	}
	return items, total, nil
}

func (r *FeedbackRepo) UpdateStatus(ctx context.Context, id uuid.UUID, status domain.FeedbackStatus) error {
	result, err := r.pool.Exec(ctx,
		"UPDATE feedback SET status = $1, updated_at = $2 WHERE id = $3",
		status, time.Now().UTC(), id,
	)
	if err != nil {
		return fmt.Errorf("feedback_repo: update_status: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("feedback_repo: update_status: %w", domain.ErrNotFound)
	}
	return nil
}
