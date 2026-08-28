package application

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

// StreamCloser deconnecte les auditeurs d'un flux. Satisfait par
// *streaming.Hub ; une interface pour que le service reste testable sans Hub.
type StreamCloser interface {
	CloseStream(streamID uuid.UUID)
}

type UserService struct {
	userRepo   domain.UserRepository
	streamRepo domain.StreamRepository
	closer     StreamCloser
}

func NewUserService(userRepo domain.UserRepository, streamRepo domain.StreamRepository, closer StreamCloser) *UserService {
	return &UserService{userRepo: userRepo, streamRepo: streamRepo, closer: closer}
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
//
// Les flux du compte disparaissent de la base par cascade, mais le Hub ne
// lit pas la base : sans cet appel, un diffuseur en direct qui supprime son
// compte continuerait d'etre entendu jusqu'a la coupure de sa connexion.
// On liste ses flux avant l'effacement, on efface, puis on ferme le direct.
func (s *UserService) DeleteUser(ctx context.Context, id uuid.UUID) error {
	streams, err := s.streamRepo.ListByOwner(ctx, id)
	if err != nil {
		return fmt.Errorf("user: delete: list streams: %w", err)
	}
	if err := s.userRepo.Delete(ctx, id); err != nil {
		return fmt.Errorf("user: delete: %w", err)
	}
	for _, st := range streams {
		if st.Status == domain.StreamStatusLive {
			s.closer.CloseStream(st.ID)
		}
	}
	return nil
}
