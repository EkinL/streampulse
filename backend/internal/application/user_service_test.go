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
	svc := application.NewUserService(repo, testutil.NewMockStreamRepo(), testutil.NewMockMusicRepo(), noopCloser{}, noopFileRemover{})
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
	svc := application.NewUserService(repo, testutil.NewMockStreamRepo(), testutil.NewMockMusicRepo(), noopCloser{}, noopFileRemover{})
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
	svc := application.NewUserService(testutil.NewMockUserRepo(), testutil.NewMockStreamRepo(), testutil.NewMockMusicRepo(), noopCloser{}, noopFileRemover{})
	if _, err := svc.GetUser(context.Background(), uuid.New()); !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("attendu ErrNotFound, obtenu %v", err)
	}
}

func TestUserService_DeleteUser(t *testing.T) {
	repo := testutil.NewMockUserRepo()
	svc := application.NewUserService(repo, testutil.NewMockStreamRepo(), testutil.NewMockMusicRepo(), noopCloser{}, noopFileRemover{})
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

type noopFileRemover struct{}

func (noopFileRemover) DeleteFile(string) error { return nil }

// recordingFileRemover note les URLs qu'on lui demande d'effacer.
type recordingFileRemover struct{ deleted []string }

func (r *recordingFileRemover) DeleteFile(url string) error {
	r.deleted = append(r.deleted, url)
	return nil
}

// Le disque n'est pas dans la base : la suppression d'un compte doit
// retrouver ses morceaux verses (avant que la cascade n'efface leurs lignes)
// et demander leur effacement, sans quoi les fichiers restent orphelins dans
// uploads/ (limite connue, docs/rgpd.md).
func TestUserService_DeleteUserRemovesUploadedFiles(t *testing.T) {
	users := testutil.NewMockUserRepo()
	music := testutil.NewMockMusicRepo()
	remover := &recordingFileRemover{}
	svc := application.NewUserService(users, testutil.NewMockStreamRepo(), music, noopCloser{}, remover)
	ctx := context.Background()

	owner := testutil.NewTestUser(domain.RoleUser)
	other := testutil.NewTestUser(domain.RoleUser)
	for _, u := range []*domain.User{owner, other} {
		if err := users.Create(ctx, u); err != nil {
			t.Fatalf("Create user: %v", err)
		}
	}
	uploaded := &domain.Music{ID: uuid.New(), Title: "Verse", URL: "http://files.test/uploads/a.mp3", UploadedBy: owner.ID}
	external := &domain.Music{ID: uuid.New(), Title: "Externe", URL: "https://cdn.test/b.mp3", UploadedBy: owner.ID}
	untouched := &domain.Music{ID: uuid.New(), Title: "Un autre compte", URL: "http://files.test/uploads/c.mp3", UploadedBy: other.ID}
	for _, m := range []*domain.Music{uploaded, external, untouched} {
		if err := music.Create(ctx, m); err != nil {
			t.Fatalf("Create music: %v", err)
		}
	}

	if err := svc.DeleteUser(ctx, owner.ID); err != nil {
		t.Fatalf("DeleteUser: %v", err)
	}

	want := map[string]bool{uploaded.URL: true, external.URL: true}
	if len(remover.deleted) != len(want) {
		t.Fatalf("URLs effacees = %v, attendu %v", remover.deleted, want)
	}
	for _, url := range remover.deleted {
		if !want[url] {
			t.Fatalf("URL effacee inattendue: %s", url)
		}
		if url == untouched.URL {
			t.Fatal("le fichier d'un autre compte n'aurait pas du etre touche")
		}
	}
}

// Un diffuseur en direct qui supprime son compte doit cesser d'etre entendu :
// seuls ses flux live sont fermes dans le Hub, pas ceux des autres.
func TestUserService_DeleteUserClosesLiveStreams(t *testing.T) {
	users := testutil.NewMockUserRepo()
	streams := testutil.NewMockStreamRepo()
	closer := &recordingCloser{}
	svc := application.NewUserService(users, streams, testutil.NewMockMusicRepo(), closer, noopFileRemover{})
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
