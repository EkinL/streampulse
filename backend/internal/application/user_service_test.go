package application_test

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/testutil"
)

func TestUserService_GetUsers(t *testing.T) {
	repo := testutil.NewMockUserRepo()
	svc := application.NewUserService(repo, testutil.NewMockStreamRepo(), noopCloser{})
	ctx := context.Background()

	for i := 0; i < 25; i++ {
		u := testutil.NewTestUser(domain.RoleUser)
		u.Email = fmt.Sprintf("user-%02d@example.com", i)
		if err := repo.Create(ctx, u); err != nil {
			t.Fatalf("Create: %v", err)
		}
	}

	t.Run("pagination normalisee", func(t *testing.T) {
		// page 0 et per_page 1000 sont ramenes a 1 et 20.
		users, total, err := svc.GetUsers(ctx, 0, 1000)
		if err != nil {
			t.Fatalf("GetUsers: %v", err)
		}
		if total != 25 || len(users) != 20 {
			t.Fatalf("total=%d len=%d, attendu 25 et 20", total, len(users))
		}
	})

	t.Run("derniere page", func(t *testing.T) {
		users, total, err := svc.GetUsers(ctx, 2, 20)
		if err != nil {
			t.Fatalf("GetUsers: %v", err)
		}
		if total != 25 || len(users) != 5 {
			t.Fatalf("total=%d len=%d, attendu 25 et 5", total, len(users))
		}
	})
}

func TestUserService_UpdateUserRole(t *testing.T) {
	repo := testutil.NewMockUserRepo()
	svc := application.NewUserService(repo, testutil.NewMockStreamRepo(), noopCloser{})
	ctx := context.Background()
	user := testutil.NewTestUser(domain.RoleUser)
	if err := repo.Create(ctx, user); err != nil {
		t.Fatalf("Create: %v", err)
	}

	t.Run("role invalide", func(t *testing.T) {
		err := svc.UpdateUserRole(ctx, user.ID, domain.Role("sorcier"))
		if !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("attendu ErrInvalidInput, obtenu %v", err)
		}
	})

	t.Run("utilisateur inconnu", func(t *testing.T) {
		err := svc.UpdateUserRole(ctx, uuid.New(), domain.RoleAdmin)
		if !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})

	t.Run("promotion", func(t *testing.T) {
		if err := svc.UpdateUserRole(ctx, user.ID, domain.RoleBroadcaster); err != nil {
			t.Fatalf("UpdateUserRole: %v", err)
		}
		got, err := svc.GetUser(ctx, user.ID)
		if err != nil {
			t.Fatalf("GetUser: %v", err)
		}
		if got.Role != domain.RoleBroadcaster {
			t.Fatalf("role = %s, attendu broadcaster", got.Role)
		}
	})
}

func TestUserService_GetUserNotFound(t *testing.T) {
	svc := application.NewUserService(testutil.NewMockUserRepo(), testutil.NewMockStreamRepo(), noopCloser{})
	if _, err := svc.GetUser(context.Background(), uuid.New()); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("attendu ErrNotFound, obtenu %v", err)
	}
}

func TestUserService_DeleteUser(t *testing.T) {
	repo := testutil.NewMockUserRepo()
	svc := application.NewUserService(repo, testutil.NewMockStreamRepo(), noopCloser{})
	ctx := context.Background()
	user := testutil.NewTestUser(domain.RoleUser)
	if err := repo.Create(ctx, user); err != nil {
		t.Fatalf("Create: %v", err)
	}

	t.Run("utilisateur inconnu", func(t *testing.T) {
		if err := svc.DeleteUser(ctx, uuid.New()); !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})

	t.Run("suppression effective", func(t *testing.T) {
		if err := svc.DeleteUser(ctx, user.ID); err != nil {
			t.Fatalf("DeleteUser: %v", err)
		}
		if _, err := svc.GetUser(ctx, user.ID); !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("le compte doit avoir disparu, obtenu %v", err)
		}
		// L'email redevient disponible : une nouvelle inscription avec la
		// meme adresse ne doit pas heurter l'ancien compte.
		if _, err := repo.FindByEmail(ctx, user.Email); !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("l'email doit etre libere, obtenu %v", err)
		}
	})

	t.Run("double suppression", func(t *testing.T) {
		if err := svc.DeleteUser(ctx, user.ID); !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})
}

type noopCloser struct{}

func (noopCloser) CloseStream(uuid.UUID) {}

// recordingCloser note les flux fermes.
type recordingCloser struct{ closed []uuid.UUID }

func (c *recordingCloser) CloseStream(id uuid.UUID) { c.closed = append(c.closed, id) }

// Un diffuseur en direct qui supprime son compte doit cesser d'etre entendu :
// seuls ses flux live sont fermes dans le Hub, pas ceux des autres.
func TestUserService_DeleteUserClosesLiveStreams(t *testing.T) {
	users := testutil.NewMockUserRepo()
	streams := testutil.NewMockStreamRepo()
	closer := &recordingCloser{}
	svc := application.NewUserService(users, streams, closer)
	ctx := context.Background()

	bc := testutil.NewTestUser(domain.RoleBroadcaster)
	other := testutil.NewTestUser(domain.RoleBroadcaster)
	for _, u := range []*domain.User{bc, other} {
		if err := users.Create(ctx, u); err != nil {
			t.Fatalf("Create: %v", err)
		}
	}
	live := testutil.NewTestStream(bc.ID)
	live.Status = domain.StreamStatusLive
	idle := testutil.NewTestStream(bc.ID)
	otherLive := testutil.NewTestStream(other.ID)
	otherLive.Status = domain.StreamStatusLive
	for _, st := range []*domain.Stream{live, idle, otherLive} {
		if err := streams.Create(ctx, st); err != nil {
			t.Fatalf("Create stream: %v", err)
		}
	}

	if err := svc.DeleteUser(ctx, bc.ID); err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}
	if len(closer.closed) != 1 || closer.closed[0] != live.ID {
		t.Fatalf("flux fermes = %v, attendu uniquement %s", closer.closed, live.ID)
	}
}
