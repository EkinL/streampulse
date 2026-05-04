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

type RefreshTokenRepo struct {
	pool *pgxpool.Pool
}

func NewRefreshTokenRepo(pool *pgxpool.Pool) *RefreshTokenRepo {
	return &RefreshTokenRepo{pool: pool}
}

func (r *RefreshTokenRepo) Store(ctx context.Context, userID uuid.UUID, tokenHash string, expiresAt interface{}) error {
	exp, ok := expiresAt.(time.Time)
	if !ok {
		return fmt.Errorf("refresh_token_repo: store: invalid expiresAt type")
	}
	_, err := r.pool.Exec(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
		userID, tokenHash, exp,
	)
	if err != nil {
		return fmt.Errorf("refresh_token_repo: store: %w", err)
	}
	return nil
}

func (r *RefreshTokenRepo) FindByHash(ctx context.Context, tokenHash string) (uuid.UUID, error) {
	var userID uuid.UUID
	var expiresAt time.Time
	err := r.pool.QueryRow(ctx,
		`SELECT user_id, expires_at FROM refresh_tokens WHERE token_hash = $1`, tokenHash,
	).Scan(&userID, &expiresAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return uuid.Nil, fmt.Errorf("refresh_token_repo: find: %w", domain.ErrNotFound)
		}
		return uuid.Nil, fmt.Errorf("refresh_token_repo: find: %w", err)
	}
	if time.Now().After(expiresAt) {
		return uuid.Nil, fmt.Errorf("refresh_token_repo: find: %w", domain.ErrTokenExpired)
	}
	return userID, nil
}

func (r *RefreshTokenRepo) DeleteByUserID(ctx context.Context, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx, "DELETE FROM refresh_tokens WHERE user_id = $1", userID)
	if err != nil {
		return fmt.Errorf("refresh_token_repo: delete_by_user: %w", err)
	}
	return nil
}

func (r *RefreshTokenRepo) DeleteExpired(ctx context.Context) error {
	_, err := r.pool.Exec(ctx, "DELETE FROM refresh_tokens WHERE expires_at < NOW()")
	if err != nil {
		return fmt.Errorf("refresh_token_repo: delete_expired: %w", err)
	}
	return nil
}
