package application

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

type UserService struct {
	userRepo domain.UserRepository
}

func NewUserService(userRepo domain.UserRepository) *UserService {
	return &UserService{userRepo: userRepo}
}

func (s *UserService) GetUsers(ctx context.Context, page, perPage int) ([]domain.User, int, error) {
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 100 {
		perPage = 20
	}
	users, total, err := s.userRepo.List(ctx, page, perPage)
	if err != nil {
		return nil, 0, fmt.Errorf("user: list: %w", err)
	}
	return users, total, nil
}

func (s *UserService) UpdateUserRole(ctx context.Context, userID uuid.UUID, role domain.Role) error {
	if !role.IsValid() {
		return fmt.Errorf("user: update_role: invalid role %q: %w", role, domain.ErrInvalidInput)
	}
	if err := s.userRepo.UpdateRole(ctx, userID, role); err != nil {
		return fmt.Errorf("user: update_role: %w", err)
	}
	return nil
}

func (s *UserService) GetUser(ctx context.Context, id uuid.UUID) (*domain.User, error) {
	user, err := s.userRepo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("user: get: %w", err)
	}
	return user, nil
}

// DeleteUser efface un compte et tout ce qui s'y rattache. Utilise a la fois
// par la personne elle-meme (DELETE /users/me) et par un administrateur qui
// traite une demande d'effacement (DELETE /admin/users/{id}).
func (s *UserService) DeleteUser(ctx context.Context, id uuid.UUID) error {
	if err := s.userRepo.Delete(ctx, id); err != nil {
		return fmt.Errorf("user: delete: %w", err)
	}
	return nil
}
