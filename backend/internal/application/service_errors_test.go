// Ce fichier couvre les branches d'erreur des services : chemins ou le
// repository echoue pour une autre raison qu'un "not found" (panne reseau,
// base injoignable). Les stubs enveloppent les mocks de testutil et ne font
// echouer que la methode visee, le reste du comportement reste reel.
package application_test

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/rs/zerolog"
	"golang.org/x/crypto/bcrypt"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/internal/infrastructure/filestore"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
	"github.com/streampulse/backend/testutil"
)

var errInfra = errors.New("panne simulee du depot")

// wantInfra verifie qu'une erreur remonte bien la panne, sans etre confondue
// avec un ErrNotFound qui donnerait un 404 au lieu d'un 500.
func wantInfra(t *testing.T, err error) {
	t.Helper()
	if !errors.Is(err, errInfra) {
		t.Fatalf("attendu la panne du depot, obtenu %v", err)
	}
	if errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("la panne ne doit pas passer pour un not found: %v", err)
	}
}

// --- stubs -----------------------------------------------------------------

type stubStreamRepo struct {
	*testutil.MockStreamRepo
	createErr, listErr, updateErr, statusErr, listenerErr error
}

func (r *stubStreamRepo) Create(ctx context.Context, s *domain.Stream) error {
	if r.createErr != nil {
		return r.createErr
	}
	return r.MockStreamRepo.Create(ctx, s)
}

func (r *stubStreamRepo) List(ctx context.Context, page, perPage int) ([]domain.Stream, int, error) {
	if r.listErr != nil {
		return nil, 0, r.listErr
	}
	return r.MockStreamRepo.List(ctx, page, perPage)
}

func (r *stubStreamRepo) Update(ctx context.Context, s *domain.Stream) error {
	if r.updateErr != nil {
		return r.updateErr
	}
	return r.MockStreamRepo.Update(ctx, s)
}

func (r *stubStreamRepo) UpdateStatus(ctx context.Context, id uuid.UUID, st domain.StreamStatus) error {
	if r.statusErr != nil {
		return r.statusErr
	}
	return r.MockStreamRepo.UpdateStatus(ctx, id, st)
}

func (r *stubStreamRepo) UpdateListenerCount(ctx context.Context, id uuid.UUID, n int) error {
	if r.listenerErr != nil {
		return r.listenerErr
	}
	return r.MockStreamRepo.UpdateListenerCount(ctx, id, n)
}

type stubPlaylistRepo struct {
	*testutil.MockPlaylistRepo
	createErr, listOwnerErr, updateErr, deleteErr, addErr, removeErr, reorderErr error
}

func (r *stubPlaylistRepo) Create(ctx context.Context, p *domain.Playlist) error {
	if r.createErr != nil {
		return r.createErr
	}
	return r.MockPlaylistRepo.Create(ctx, p)
}

func (r *stubPlaylistRepo) ListByOwner(ctx context.Context, ownerID uuid.UUID, page, perPage int) ([]domain.Playlist, int, error) {
	if r.listOwnerErr != nil {
		return nil, 0, r.listOwnerErr
	}
	return r.MockPlaylistRepo.ListByOwner(ctx, ownerID, page, perPage)
}

func (r *stubPlaylistRepo) Update(ctx context.Context, p *domain.Playlist) error {
	if r.updateErr != nil {
		return r.updateErr
	}
	return r.MockPlaylistRepo.Update(ctx, p)
}

func (r *stubPlaylistRepo) Delete(ctx context.Context, id uuid.UUID) error {
	if r.deleteErr != nil {
		return r.deleteErr
	}
	return r.MockPlaylistRepo.Delete(ctx, id)
}

func (r *stubPlaylistRepo) AddTrack(ctx context.Context, playlistID uuid.UUID, tr *domain.Track) error {
	if r.addErr != nil {
		return r.addErr
	}
	return r.MockPlaylistRepo.AddTrack(ctx, playlistID, tr)
}

func (r *stubPlaylistRepo) RemoveTrack(ctx context.Context, playlistID, trackID uuid.UUID) error {
	if r.removeErr != nil {
		return r.removeErr
	}
	return r.MockPlaylistRepo.RemoveTrack(ctx, playlistID, trackID)
}

func (r *stubPlaylistRepo) ReorderTracks(ctx context.Context, playlistID uuid.UUID, ids []uuid.UUID) error {
	if r.reorderErr != nil {
		return r.reorderErr
	}
	return r.MockPlaylistRepo.ReorderTracks(ctx, playlistID, ids)
}

// flakyFindPlaylistRepo fait echouer le N-ieme FindByID : sert a couvrir la
// relecture de ReorderTracks, qui relit la playlist apres l'ecriture.
type flakyFindPlaylistRepo struct {
	*testutil.MockPlaylistRepo
	calls  int
	failOn int
}

func (r *flakyFindPlaylistRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Playlist, error) {
	r.calls++
	if r.calls == r.failOn {
		return nil, errInfra
	}
	return r.MockPlaylistRepo.FindByID(ctx, id)
}

type stubMusicRepo struct {
	*testutil.MockMusicRepo
	createErr, listErr, searchErr, updateErr, deleteErr error
}

func (r *stubMusicRepo) Create(ctx context.Context, m *domain.Music) error {
	if r.createErr != nil {
		return r.createErr
	}
	return r.MockMusicRepo.Create(ctx, m)
}

func (r *stubMusicRepo) List(ctx context.Context, page, perPage int) ([]domain.Music, int, error) {
	if r.listErr != nil {
		return nil, 0, r.listErr
	}
	return r.MockMusicRepo.List(ctx, page, perPage)
}

func (r *stubMusicRepo) Search(ctx context.Context, q string, page, perPage int) ([]domain.Music, int, error) {
	if r.searchErr != nil {
		return nil, 0, r.searchErr
	}
	return r.MockMusicRepo.Search(ctx, q, page, perPage)
}

func (r *stubMusicRepo) Update(ctx context.Context, m *domain.Music) error {
	if r.updateErr != nil {
		return r.updateErr
	}
	return r.MockMusicRepo.Update(ctx, m)
}

func (r *stubMusicRepo) Delete(ctx context.Context, id uuid.UUID) error {
	if r.deleteErr != nil {
		return r.deleteErr
	}
	return r.MockMusicRepo.Delete(ctx, id)
}

type stubRefreshRepo struct {
	*testutil.MockRefreshTokenRepo
	storeErr error
}

func (r *stubRefreshRepo) Store(ctx context.Context, userID uuid.UUID, hash string, expiresAt interface{}) error {
	if r.storeErr != nil {
		return r.storeErr
	}
	return r.MockRefreshTokenRepo.Store(ctx, userID, hash, expiresAt)
}

// errReader echoue a la premiere lecture : simule un upload coupe en plein vol.
type errReader struct{}

func (errReader) Read([]byte) (int, error) { return 0, errInfra }

// --- StreamService ---------------------------------------------------------

func TestStreamService_RepoFailures(t *testing.T) {
	ctx := context.Background()
	ownerID := uuid.New()
	hub := streaming.NewHub(zerolog.Nop())

	newSvc := func(repo domain.StreamRepository) *application.StreamService {
		return application.NewStreamService(repo, hub)
	}

	t.Run("create", func(t *testing.T) {
		svc := newSvc(&stubStreamRepo{MockStreamRepo: testutil.NewMockStreamRepo(), createErr: errInfra})
		_, err := svc.CreateStream(ctx, application.CreateStreamInput{Title: "t", OwnerID: ownerID})
		wantInfra(t, err)
	})

	t.Run("list", func(t *testing.T) {
		svc := newSvc(&stubStreamRepo{MockStreamRepo: testutil.NewMockStreamRepo(), listErr: errInfra})
		_, _, err := svc.ListStreams(ctx, 1, 20)
		wantInfra(t, err)
	})

	t.Run("update", func(t *testing.T) {
		repo := &stubStreamRepo{MockStreamRepo: testutil.NewMockStreamRepo(), updateErr: errInfra}
		svc := newSvc(repo)
		created, err := svc.CreateStream(ctx, application.CreateStreamInput{Title: "t", OwnerID: ownerID})
		if err != nil {
			t.Fatalf("create: %v", err)
		}
		_, err = svc.UpdateStream(ctx, created.ID, ownerID, "t2", "d2")
		wantInfra(t, err)
	})

	t.Run("start update status", func(t *testing.T) {
		repo := &stubStreamRepo{MockStreamRepo: testutil.NewMockStreamRepo(), statusErr: errInfra}
		svc := newSvc(repo)
		created, err := svc.CreateStream(ctx, application.CreateStreamInput{Title: "t", OwnerID: ownerID})
		if err != nil {
			t.Fatalf("create: %v", err)
		}
		wantInfra(t, svc.StartStream(ctx, created.ID, ownerID))
	})

	t.Run("stop update status", func(t *testing.T) {
		repo := &stubStreamRepo{MockStreamRepo: testutil.NewMockStreamRepo(), statusErr: errInfra}
		svc := newSvc(repo)
		created, err := svc.CreateStream(ctx, application.CreateStreamInput{Title: "t", OwnerID: ownerID})
		if err != nil {
			t.Fatalf("create: %v", err)
		}
		wantInfra(t, svc.StopStream(ctx, created.ID, ownerID))
	})

	t.Run("stop update listener count", func(t *testing.T) {
		repo := &stubStreamRepo{MockStreamRepo: testutil.NewMockStreamRepo(), listenerErr: errInfra}
		svc := newSvc(repo)
		created, err := svc.CreateStream(ctx, application.CreateStreamInput{Title: "t", OwnerID: ownerID})
		if err != nil {
			t.Fatalf("create: %v", err)
		}
		wantInfra(t, svc.StopStream(ctx, created.ID, ownerID))
	})
}

func TestStreamService_UpdateAndStop(t *testing.T) {
	svc, _ := newStreamService()
	ctx := context.Background()
	ownerID := uuid.New()
	otherID := uuid.New()

	created, err := svc.CreateStream(ctx, application.CreateStreamInput{Title: "avant", OwnerID: ownerID})
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	t.Run("update ok", func(t *testing.T) {
		updated, err := svc.UpdateStream(ctx, created.ID, ownerID, "apres", "desc")
		if err != nil {
			t.Fatalf("update: %v", err)
		}
		if updated.Title != "apres" || updated.Description != "desc" {
			t.Fatalf("update non applique: %+v", updated)
		}
	})

	t.Run("update not owner", func(t *testing.T) {
		if _, err := svc.UpdateStream(ctx, created.ID, otherID, "x", "y"); !errors.Is(err, domain.ErrNotOwner) {
			t.Fatalf("attendu ErrNotOwner, obtenu %v", err)
		}
	})

	t.Run("update not found", func(t *testing.T) {
		if _, err := svc.UpdateStream(ctx, uuid.New(), ownerID, "x", "y"); !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})

	t.Run("stop not owner", func(t *testing.T) {
		if err := svc.StopStream(ctx, created.ID, otherID); !errors.Is(err, domain.ErrNotOwner) {
			t.Fatalf("attendu ErrNotOwner, obtenu %v", err)
		}
	})

	t.Run("stop not found", func(t *testing.T) {
		if err := svc.StopStream(ctx, uuid.New(), ownerID); !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})

	t.Run("stop ok", func(t *testing.T) {
		if err := svc.StartStream(ctx, created.ID, ownerID); err != nil {
			t.Fatalf("start: %v", err)
		}
		if err := svc.StopStream(ctx, created.ID, ownerID); err != nil {
			t.Fatalf("stop: %v", err)
		}
		got, err := svc.GetStream(ctx, created.ID)
		if err != nil {
			t.Fatalf("get: %v", err)
		}
		if got.Status != domain.StreamStatusEnded {
			t.Fatalf("statut attendu ended, obtenu %q", got.Status)
		}
		if got.ListenerCount != 0 {
			t.Fatalf("compteur d'auditeurs attendu a 0, obtenu %d", got.ListenerCount)
		}
	})
}

func TestStreamService_ListNormalizesPagination(t *testing.T) {
	svc, _ := newStreamService()
	ctx := context.Background()
	if _, err := svc.CreateStream(ctx, application.CreateStreamInput{Title: "t", OwnerID: uuid.New()}); err != nil {
		t.Fatalf("create: %v", err)
	}

	// page 0 et per_page hors bornes doivent etre ramenes aux defauts.
	streams, total, err := svc.ListStreams(ctx, 0, 1000)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if total != 1 || len(streams) != 1 {
		t.Fatalf("attendu 1 flux, obtenu %d (total %d)", len(streams), total)
	}
}

func TestStreamService_HubAccessor(t *testing.T) {
	repo := testutil.NewMockStreamRepo()
	hub := streaming.NewHub(zerolog.Nop())
	svc := application.NewStreamService(repo, hub)
	if svc.Hub() != hub {
		t.Fatal("Hub() doit rendre le hub injecte a la construction")
	}
}

// --- PlaylistService -------------------------------------------------------

func TestPlaylistService_ListPlaylists(t *testing.T) {
	repo := testutil.NewMockPlaylistRepo()
	svc := application.NewPlaylistService(repo)
	ctx := context.Background()
	ownerID := uuid.New()

	for i := 0; i < 3; i++ {
		if _, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{Name: "p", OwnerID: ownerID}); err != nil {
			t.Fatalf("create: %v", err)
		}
	}

	// Pagination hors bornes normalisee, et seules les playlists du
	// proprietaire ressortent.
	playlists, total, err := svc.ListPlaylists(ctx, ownerID, 0, 0)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if total != 3 || len(playlists) != 3 {
		t.Fatalf("attendu 3 playlists, obtenu %d (total %d)", len(playlists), total)
	}

	if _, _, err := svc.ListPlaylists(ctx, uuid.New(), 1, 20); err != nil {
		t.Fatalf("list autre proprietaire: %v", err)
	}
}

func TestPlaylistService_ListPublicPlaylists(t *testing.T) {
	repo := testutil.NewMockPlaylistRepo()
	svc := application.NewPlaylistService(repo)
	ctx := context.Background()

	if _, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{Name: "publique", OwnerID: uuid.New(), IsPublic: true}); err != nil {
		t.Fatalf("create: %v", err)
	}
	if _, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{Name: "privee", OwnerID: uuid.New()}); err != nil {
		t.Fatalf("create: %v", err)
	}

	playlists, total, err := svc.ListPublicPlaylists(ctx, 0, 0)
	if err != nil {
		t.Fatalf("list public: %v", err)
	}
	if total != 1 || len(playlists) != 1 || playlists[0].Name != "publique" {
		t.Fatalf("attendu la seule playlist publique, obtenu %+v (total %d)", playlists, total)
	}

	// Page au-dela du total : liste vide, total conserve.
	playlists, total, err = svc.ListPublicPlaylists(ctx, 99, 20)
	if err != nil {
		t.Fatalf("list public page 99: %v", err)
	}
	if total != 1 || len(playlists) != 0 {
		t.Fatalf("attendu 0 playlist (total 1), obtenu %d (total %d)", len(playlists), total)
	}
}

func TestPlaylistService_RepoFailures(t *testing.T) {
	ctx := context.Background()
	ownerID := uuid.New()

	// newOwned prepare un service dont le stub echoue sur une methode, avec
	// une playlist du proprietaire deja en place.
	newOwned := func(t *testing.T, mutate func(*stubPlaylistRepo)) (*application.PlaylistService, *domain.Playlist) {
		t.Helper()
		repo := &stubPlaylistRepo{MockPlaylistRepo: testutil.NewMockPlaylistRepo()}
		svc := application.NewPlaylistService(repo)
		created, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{Name: "p", OwnerID: ownerID})
		if err != nil {
			t.Fatalf("create: %v", err)
		}
		mutate(repo)
		return svc, created
	}

	t.Run("create", func(t *testing.T) {
		repo := &stubPlaylistRepo{MockPlaylistRepo: testutil.NewMockPlaylistRepo(), createErr: errInfra}
		svc := application.NewPlaylistService(repo)
		_, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{Name: "p", OwnerID: ownerID})
		wantInfra(t, err)
	})

	t.Run("list by owner", func(t *testing.T) {
		repo := &stubPlaylistRepo{MockPlaylistRepo: testutil.NewMockPlaylistRepo(), listOwnerErr: errInfra}
		svc := application.NewPlaylistService(repo)
		_, _, err := svc.ListPlaylists(ctx, ownerID, 1, 20)
		wantInfra(t, err)
	})

	t.Run("update", func(t *testing.T) {
		svc, created := newOwned(t, func(r *stubPlaylistRepo) { r.updateErr = errInfra })
		_, err := svc.UpdatePlaylist(ctx, application.UpdatePlaylistInput{ID: created.ID, Name: "n", OwnerID: ownerID})
		wantInfra(t, err)
	})

	t.Run("update not found", func(t *testing.T) {
		svc := application.NewPlaylistService(testutil.NewMockPlaylistRepo())
		_, err := svc.UpdatePlaylist(ctx, application.UpdatePlaylistInput{ID: uuid.New(), Name: "n", OwnerID: ownerID})
		if !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})

	t.Run("delete", func(t *testing.T) {
		svc, created := newOwned(t, func(r *stubPlaylistRepo) { r.deleteErr = errInfra })
		wantInfra(t, svc.DeletePlaylist(ctx, created.ID, ownerID))
	})

	t.Run("delete not found", func(t *testing.T) {
		svc := application.NewPlaylistService(testutil.NewMockPlaylistRepo())
		if err := svc.DeletePlaylist(ctx, uuid.New(), ownerID); !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})

	t.Run("add track", func(t *testing.T) {
		svc, created := newOwned(t, func(r *stubPlaylistRepo) { r.addErr = errInfra })
		_, err := svc.AddTrack(ctx, application.AddTrackInput{PlaylistID: created.ID, OwnerID: ownerID, Title: "t", URL: "u"})
		wantInfra(t, err)
	})

	t.Run("remove track", func(t *testing.T) {
		svc, created := newOwned(t, func(r *stubPlaylistRepo) { r.removeErr = errInfra })
		wantInfra(t, svc.RemoveTrack(ctx, created.ID, uuid.New(), ownerID))
	})

	t.Run("remove track playlist not found", func(t *testing.T) {
		svc := application.NewPlaylistService(testutil.NewMockPlaylistRepo())
		if err := svc.RemoveTrack(ctx, uuid.New(), uuid.New(), ownerID); !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})

	t.Run("reorder write", func(t *testing.T) {
		svc, created := newOwned(t, func(r *stubPlaylistRepo) { r.reorderErr = errInfra })
		_, err := svc.ReorderTracks(ctx, application.ReorderTracksInput{
			PlaylistID: created.ID, OwnerID: ownerID, TrackIDs: []uuid.UUID{uuid.New()},
		})
		wantInfra(t, err)
	})

	t.Run("reorder playlist not found", func(t *testing.T) {
		svc := application.NewPlaylistService(testutil.NewMockPlaylistRepo())
		_, err := svc.ReorderTracks(ctx, application.ReorderTracksInput{
			PlaylistID: uuid.New(), OwnerID: ownerID, TrackIDs: []uuid.UUID{uuid.New()},
		})
		if !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})

	t.Run("reorder reread", func(t *testing.T) {
		// La relecture apres ecriture est le 2e FindByID du service.
		repo := &flakyFindPlaylistRepo{MockPlaylistRepo: testutil.NewMockPlaylistRepo(), failOn: 2}
		svc := application.NewPlaylistService(repo)
		created, err := svc.CreatePlaylist(ctx, application.CreatePlaylistInput{Name: "p", OwnerID: ownerID})
		if err != nil {
			t.Fatalf("create: %v", err)
		}
		track, err := svc.AddTrack(ctx, application.AddTrackInput{PlaylistID: created.ID, OwnerID: ownerID, Title: "t", URL: "u"})
		if err != nil {
			t.Fatalf("add track: %v", err)
		}
		repo.calls = 0
		_, err = svc.ReorderTracks(ctx, application.ReorderTracksInput{
			PlaylistID: created.ID, OwnerID: ownerID, TrackIDs: []uuid.UUID{track.ID},
		})
		wantInfra(t, err)
	})
}

// --- MusicService ----------------------------------------------------------

func TestMusicService_RepoFailures(t *testing.T) {
	ctx := context.Background()
	uploaderID := uuid.New()

	newSvc := func(repo domain.MusicRepository) *application.MusicService {
		store := filestore.NewFileStore(t.TempDir(), "http://files.test/uploads")
		return application.NewMusicService(repo, store)
	}

	t.Run("upload save file", func(t *testing.T) {
		svc := newSvc(testutil.NewMockMusicRepo())
		_, err := svc.UploadMusic(ctx, "t", "a", "al", 180, "song.mp3", errReader{}, uploaderID)
		wantInfra(t, err)
	})

	t.Run("upload create", func(t *testing.T) {
		svc := newSvc(&stubMusicRepo{MockMusicRepo: testutil.NewMockMusicRepo(), createErr: errInfra})
		_, err := svc.UploadMusic(ctx, "t", "a", "al", 180, "song.mp3", strings.NewReader("audio"), uploaderID)
		wantInfra(t, err)
	})

	t.Run("add by url create", func(t *testing.T) {
		svc := newSvc(&stubMusicRepo{MockMusicRepo: testutil.NewMockMusicRepo(), createErr: errInfra})
		_, err := svc.AddMusicByURL(ctx, "t", "a", "al", 180, "http://x/y.mp3", uploaderID)
		wantInfra(t, err)
	})

	t.Run("list", func(t *testing.T) {
		svc := newSvc(&stubMusicRepo{MockMusicRepo: testutil.NewMockMusicRepo(), listErr: errInfra})
		_, _, err := svc.ListMusic(ctx, 1, 20)
		wantInfra(t, err)
	})

	t.Run("search", func(t *testing.T) {
		svc := newSvc(&stubMusicRepo{MockMusicRepo: testutil.NewMockMusicRepo(), searchErr: errInfra})
		_, _, err := svc.SearchMusic(ctx, "q", 1, 20)
		wantInfra(t, err)
	})

	t.Run("update", func(t *testing.T) {
		repo := &stubMusicRepo{MockMusicRepo: testutil.NewMockMusicRepo()}
		svc := newSvc(repo)
		created, err := svc.AddMusicByURL(ctx, "t", "a", "al", 180, "http://x/y.mp3", uploaderID)
		if err != nil {
			t.Fatalf("add: %v", err)
		}
		repo.updateErr = errInfra
		_, err = svc.UpdateMusic(ctx, created.ID, uploaderID, "t2", "a2", "al2", "")
		wantInfra(t, err)
	})

	t.Run("delete", func(t *testing.T) {
		repo := &stubMusicRepo{MockMusicRepo: testutil.NewMockMusicRepo()}
		svc := newSvc(repo)
		created, err := svc.AddMusicByURL(ctx, "t", "a", "al", 180, "http://x/y.mp3", uploaderID)
		if err != nil {
			t.Fatalf("add: %v", err)
		}
		repo.deleteErr = errInfra
		wantInfra(t, svc.DeleteMusic(ctx, created.ID, uploaderID))
	})
}

func TestMusicService_SearchNormalizesPagination(t *testing.T) {
	repo := testutil.NewMockMusicRepo()
	store := filestore.NewFileStore(t.TempDir(), "http://files.test/uploads")
	svc := application.NewMusicService(repo, store)
	ctx := context.Background()

	if _, err := svc.AddMusicByURL(ctx, "Bohemian Rhapsody", "Queen", "", 355, "http://x/y.mp3", uuid.New()); err != nil {
		t.Fatalf("add: %v", err)
	}

	tracks, total, err := svc.SearchMusic(ctx, "queen", 0, 1000)
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if total != 1 || len(tracks) != 1 {
		t.Fatalf("attendu 1 morceau, obtenu %d (total %d)", len(tracks), total)
	}
}

// --- AuthService -----------------------------------------------------------

func newAuthServiceWithRepos(userRepo domain.UserRepository, refreshRepo domain.RefreshTokenRepository) *application.AuthService {
	jwt := auth.NewJWTManager("unit-test-secret", 15*time.Minute, 24*time.Hour)
	return application.NewAuthService(userRepo, refreshRepo, jwt, nil)
}

func TestAuthService_ValidateToken(t *testing.T) {
	svc := newAuthServiceWithRepos(testutil.NewMockUserRepo(), testutil.NewMockRefreshTokenRepo())
	ctx := context.Background()

	result, err := svc.Register(ctx, application.RegisterInput{
		Email: "valid@test.io", Username: "valid", Password: "longenough", AcceptedTerms: true})
	if err != nil {
		t.Fatalf("register: %v", err)
	}

	claims, err := svc.ValidateToken(result.AccessToken)
	if err != nil {
		t.Fatalf("validate: %v", err)
	}
	if claims.Email != "valid@test.io" || claims.Role != domain.RoleUser {
		t.Fatalf("claims inattendues: %+v", claims)
	}

	if _, err := svc.ValidateToken("pas-un-jwt"); err == nil {
		t.Fatal("un jeton invalide doit etre rejete")
	}
}

func TestAuthService_RepoFailures(t *testing.T) {
	ctx := context.Background()

	t.Run("register hash password", func(t *testing.T) {
		svc := newAuthServiceWithRepos(testutil.NewMockUserRepo(), testutil.NewMockRefreshTokenRepo())
		// bcrypt refuse les mots de passe de plus de 72 octets.
		_, err := svc.Register(ctx, application.RegisterInput{
			Email: "long@test.io", Username: "long", Password: strings.Repeat("x", 80), AcceptedTerms: true})
		if err == nil {
			t.Fatal("attendu une erreur bcrypt")
		}
	})

	t.Run("register store refresh token", func(t *testing.T) {
		refresh := &stubRefreshRepo{MockRefreshTokenRepo: testutil.NewMockRefreshTokenRepo(), storeErr: errInfra}
		svc := newAuthServiceWithRepos(testutil.NewMockUserRepo(), refresh)
		_, err := svc.Register(ctx, application.RegisterInput{
			Email: "store@test.io", Username: "store", Password: "longenough", AcceptedTerms: true})
		wantInfra(t, err)
	})

	t.Run("login store refresh token", func(t *testing.T) {
		userRepo := testutil.NewMockUserRepo()
		hash, err := bcrypt.GenerateFromPassword([]byte("longenough"), bcrypt.MinCost)
		if err != nil {
			t.Fatalf("bcrypt: %v", err)
		}
		user := testutil.NewTestUser(domain.RoleUser)
		user.Email = "login@test.io"
		user.PasswordHash = string(hash)
		if err := userRepo.Create(ctx, user); err != nil {
			t.Fatalf("create user: %v", err)
		}

		refresh := &stubRefreshRepo{MockRefreshTokenRepo: testutil.NewMockRefreshTokenRepo(), storeErr: errInfra}
		svc := newAuthServiceWithRepos(userRepo, refresh)
		_, err = svc.Login(ctx, application.LoginInput{Email: "login@test.io", Password: "longenough"})
		wantInfra(t, err)
	})

	t.Run("refresh unknown user", func(t *testing.T) {
		refresh := testutil.NewMockRefreshTokenRepo()
		// Jeton en base mais compte disparu : la relecture du compte echoue.
		if err := refresh.Store(ctx, uuid.New(), auth.HashToken("orphan-token"), nil); err != nil {
			t.Fatalf("store: %v", err)
		}
		svc := newAuthServiceWithRepos(testutil.NewMockUserRepo(), refresh)
		_, err := svc.RefreshToken(ctx, "orphan-token")
		if !errors.Is(err, domain.ErrNotFound) {
			t.Fatalf("attendu ErrNotFound, obtenu %v", err)
		}
	})

	t.Run("refresh store new token", func(t *testing.T) {
		userRepo := testutil.NewMockUserRepo()
		user := testutil.NewTestUser(domain.RoleUser)
		if err := userRepo.Create(ctx, user); err != nil {
			t.Fatalf("create user: %v", err)
		}
		refresh := &stubRefreshRepo{MockRefreshTokenRepo: testutil.NewMockRefreshTokenRepo()}
		if err := refresh.MockRefreshTokenRepo.Store(ctx, user.ID, auth.HashToken("valid-token"), nil); err != nil {
			t.Fatalf("store: %v", err)
		}
		refresh.storeErr = errInfra
		svc := newAuthServiceWithRepos(userRepo, refresh)
		_, err := svc.RefreshToken(ctx, "valid-token")
		wantInfra(t, err)
	})
}
