package application

import (
	"context"
	"fmt"
	"regexp"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
)

// Memes contraintes que cote client (mobile/lib/core/utils/validators.dart) :
// dupliquees ici parce que le client ne peut pas etre la seule barriere.
var (
	profileEmailFormat    = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
	profileUsernameFormat = regexp.MustCompile(`^[a-zA-Z0-9_]{3,30}$`)
)

// StreamCloser deconnecte les auditeurs d'un flux. Satisfait par
// *streaming.Hub ; une interface pour que le service reste testable sans Hub.
type StreamCloser interface {
	CloseStream(streamID uuid.UUID)
}

// FileRemover efface un fichier uploade a partir de son URL publique.
// Satisfait par *filestore.FileStore ; une interface pour que le service
// reste testable sans toucher au disque, et parce qu'un lien externe (ajoute
// via AddMusicByURL) n'est pas cense etre efface : c'est a l'implementation
// de le reconnaitre et de l'ignorer (voir FileStore.DeleteFile).
type FileRemover interface {
	DeleteFile(url string) error
}

type UserService struct {
	userRepo    domain.UserRepository
	streamRepo  domain.StreamRepository
	musicRepo   domain.MusicRepository
	closer      StreamCloser
	fileRemover FileRemover
}

func NewUserService(userRepo domain.UserRepository, streamRepo domain.StreamRepository, musicRepo domain.MusicRepository, closer StreamCloser, fileRemover FileRemover) *UserService {
	return &UserService{
		userRepo:    userRepo,
		streamRepo:  streamRepo,
		musicRepo:   musicRepo,
		closer:      closer,
		fileRemover: fileRemover,
	}
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

// UpdateProfile change l'email et le nom d'utilisateur du compte. C'est le
// droit de rectification du RGPD (art. 16) : jusqu'ici seul un administrateur
// pouvait modifier ces champs, directement en base (docs/rgpd.md).
func (s *UserService) UpdateProfile(ctx context.Context, id uuid.UUID, email, username string) (*domain.User, error) {
	if !profileEmailFormat.MatchString(email) || !profileUsernameFormat.MatchString(username) {
		return nil, fmt.Errorf("user: update_profile: %w", domain.ErrInvalidInput)
	}
	if err := s.userRepo.UpdateProfile(ctx, id, email, username); err != nil {
		return nil, fmt.Errorf("user: update_profile: %w", err)
	}
	user, err := s.userRepo.FindByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("user: update_profile: %w", err)
	}
	return user, nil
}

// DeleteUser efface un compte et tout ce qui s'y rattache. Utilise a la fois
// par la personne elle-meme (DELETE /users/me) et par un administrateur qui
// traite une demande d'effacement (DELETE /admin/users/{id}).
//
// Les flux et les morceaux du compte disparaissent de la base par cascade,
// mais deux choses n'y vivent pas :
//   - le Hub, qui ne lit pas la base : sans cet appel, un diffuseur en direct
//     qui supprime son compte continuerait d'etre entendu jusqu'a la coupure
//     de sa connexion ;
//   - les fichiers audio verses dans uploads/, qui restent sur disque et
//     servis par leur URL si personne ne les efface explicitement (limite
//     connue, docs/rgpd.md).
//
// Les deux se lisent avant l'effacement (la cascade fait disparaitre les
// lignes qui les decrivent), puis s'appliquent apres : fermer un direct ou
// effacer un fichier avant que le compte n'ait fini de disparaitre n'a pas
// de sens si l'effacement echoue ensuite.
func (s *UserService) DeleteUser(ctx context.Context, id uuid.UUID) error {
	streams, err := s.streamRepo.ListByOwner(ctx, id)
	if err != nil {
		return fmt.Errorf("user: delete: list streams: %w", err)
	}
	tracks, err := s.musicRepo.AllByUploader(ctx, id)
	if err != nil {
		return fmt.Errorf("user: delete: list music: %w", err)
	}

	if err := s.userRepo.Delete(ctx, id); err != nil {
		return fmt.Errorf("user: delete: %w", err)
	}

	for _, st := range streams {
		if st.Status == domain.StreamStatusLive {
			s.closer.CloseStream(st.ID)
		}
	}
	for _, m := range tracks {
		_ = s.fileRemover.DeleteFile(m.URL)
	}
	return nil
}
