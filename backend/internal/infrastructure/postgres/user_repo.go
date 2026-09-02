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

type UserRepo struct {
	pool *pgxpool.Pool
}

func NewUserRepo(pool *pgxpool.Pool) *UserRepo {
	return &UserRepo{pool: pool}
}

func (r *UserRepo) Create(ctx context.Context, user *domain.User) error {
	query := `
		INSERT INTO users (id, email, username, password_hash, role, terms_accepted_at, auth_provider, provider_subject, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
	`
	now := time.Now().UTC()
	if user.ID == uuid.Nil {
		user.ID = uuid.New()
	}
	if user.AuthProvider == "" {
		user.AuthProvider = domain.ProviderLocal
	}
	user.CreatedAt = now
	user.UpdatedAt = now

	_, err := r.pool.Exec(ctx, query,
		user.ID, user.Email, user.Username, user.PasswordHash, string(user.Role), user.TermsAcceptedAt,
		user.AuthProvider, nullIfEmpty(user.ProviderSubject), user.CreatedAt, user.UpdatedAt,
	)
	if err != nil {
		if isDuplicateKeyError(err) {
			return fmt.Errorf("user_repo: create: %w", domain.ErrAlreadyExists)
		}
		return fmt.Errorf("user_repo: create: %w", err)
	}
	return nil
}

func (r *UserRepo) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
	query := userSelectColumns + ` FROM users WHERE email = $1`
	return r.scanUser(ctx, query, email)
}

func (r *UserRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.User, error) {
	query := userSelectColumns + ` FROM users WHERE id = $1`
	return r.scanUser(ctx, query, id)
}

func (r *UserRepo) FindByProviderSubject(ctx context.Context, provider, subject string) (*domain.User, error) {
	query := userSelectColumns + ` FROM users WHERE auth_provider = $1 AND provider_subject = $2`
	return r.scanUser(ctx, query, provider, subject)
}

func (r *UserRepo) LinkProviderSubject(ctx context.Context, id uuid.UUID, provider, subject string) error {
	result, err := r.pool.Exec(ctx,
		"UPDATE users SET auth_provider = $1, provider_subject = $2, updated_at = $3 WHERE id = $4",
		provider, subject, time.Now().UTC(), id,
	)
	if err != nil {
		if isDuplicateKeyError(err) {
			return fmt.Errorf("user_repo: link_provider: %w", domain.ErrAlreadyExists)
		}
		return fmt.Errorf("user_repo: link_provider: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("user_repo: link_provider: %w", domain.ErrNotFound)
	}
	return nil
}

func (r *UserRepo) List(ctx context.Context, page, perPage int) ([]domain.User, int, error) {
	offset := (page - 1) * perPage

	var total int
	err := r.pool.QueryRow(ctx, "SELECT COUNT(*) FROM users").Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("user_repo: list count: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		userSelectColumns+" FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2",
		perPage, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("user_repo: list: %w", err)
	}
	defer rows.Close()

	var users []domain.User
	for rows.Next() {
		var u domain.User
		var role string
		var providerSubject *string
		if err := rows.Scan(&u.ID, &u.Email, &u.Username, &u.PasswordHash, &role, &u.TermsAcceptedAt, &u.AuthProvider, &providerSubject, &u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, 0, fmt.Errorf("user_repo: list scan: %w", err)
		}
		u.Role = domain.Role(role)
		if providerSubject != nil {
			u.ProviderSubject = *providerSubject
		}
		users = append(users, u)
	}
	return users, total, nil
}

func (r *UserRepo) UpdateRole(ctx context.Context, id uuid.UUID, role domain.Role) error {
	result, err := r.pool.Exec(ctx,
		"UPDATE users SET role = $1, updated_at = $2 WHERE id = $3",
		string(role), time.Now().UTC(), id,
	)
	if err != nil {
		return fmt.Errorf("user_repo: update_role: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("user_repo: update_role: %w", domain.ErrNotFound)
	}
	return nil
}

// UpdateProfile change l'email et le nom d'utilisateur. La contrainte
// d'unicite sur l'email (migration 001) fait echouer la requete avec
// ErrAlreadyExists si l'adresse est deja prise par un autre compte.
func (r *UserRepo) UpdateProfile(ctx context.Context, id uuid.UUID, email, username string) error {
	result, err := r.pool.Exec(ctx,
		"UPDATE users SET email = $1, username = $2, updated_at = $3 WHERE id = $4",
		email, username, time.Now().UTC(), id,
	)
	if err != nil {
		if isDuplicateKeyError(err) {
			return fmt.Errorf("user_repo: update_profile: %w", domain.ErrAlreadyExists)
		}
		return fmt.Errorf("user_repo: update_profile: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("user_repo: update_profile: %w", domain.ErrNotFound)
	}
	return nil
}

// Delete supprime la ligne users. Les tables liees (refresh_tokens, streams,
// playlists, favorites, music, music_favorites) declarent toutes
// ON DELETE CASCADE vers users(id) : une seule requete efface l'ensemble des
// donnees de la personne, sans risque d'oublier une table.
func (r *UserRepo) Delete(ctx context.Context, id uuid.UUID) error {
	result, err := r.pool.Exec(ctx, "DELETE FROM users WHERE id = $1", id)
	if err != nil {
		return fmt.Errorf("user_repo: delete: %w", err)
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("user_repo: delete: %w", domain.ErrNotFound)
	}
	return nil
}

// userSelectColumns liste les colonnes lues par scanUser : les deux doivent
// evoluer ensemble.
const userSelectColumns = `SELECT id, email, username, password_hash, role, terms_accepted_at, auth_provider, provider_subject, created_at, updated_at`

func (r *UserRepo) scanUser(ctx context.Context, query string, args ...interface{}) (*domain.User, error) {
	var u domain.User
	var role string
	var providerSubject *string
	err := r.pool.QueryRow(ctx, query, args...).Scan(
		&u.ID, &u.Email, &u.Username, &u.PasswordHash, &role, &u.TermsAcceptedAt, &u.AuthProvider, &providerSubject, &u.CreatedAt, &u.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("user_repo: find: %w", domain.ErrNotFound)
		}
		return nil, fmt.Errorf("user_repo: find: %w", err)
	}
	u.Role = domain.Role(role)
	if providerSubject != nil {
		u.ProviderSubject = *providerSubject
	}
	return &u, nil
}

// nullIfEmpty stocke NULL plutot que ” : l'index unique partiel de la
// migration 007 ne porte que sur les lignes a provider_subject non NULL.
func nullIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}

func isDuplicateKeyError(err error) bool {
	return err != nil && !errors.Is(err, pgx.ErrNoRows) && containsDuplicateKey(err.Error())
}

func containsDuplicateKey(s string) bool {
	return len(s) > 0 && (contains(s, "duplicate key") || contains(s, "23505"))
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && searchString(s, sub)
}

func searchString(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
