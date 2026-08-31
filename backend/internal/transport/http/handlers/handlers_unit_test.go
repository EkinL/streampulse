// Harnais partage des tests unitaires de handlers : les scenarios de bout en
// bout (routeur complet, base reelle) vivent dans internal/integration ; ici
// chaque handler est appele directement, avec des services reels branches sur
// les mocks de testutil, pour prouver les reponses des branches que
// l'integration ne peut pas atteindre (claims absentes car le middleware les
// pose toujours, identifiants invalides, panne du depot).
package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/internal/infrastructure/observability"
	"github.com/streampulse/backend/internal/transport/http/middleware"
	"github.com/streampulse/backend/testutil"
)

var errInfra = errors.New("panne simulee du depot")

// Les compteurs Prometheus s'enregistrent dans le registre global : un seul
// jeu de metriques pour tout le binaire de test, comme en production.
var testMetrics = observability.NewMetrics()

func unitClaims(userID uuid.UUID, role domain.Role) *auth.Claims {
	return &auth.Claims{UserID: userID.String(), Username: "unit", Role: role}
}

func reqWithClaims(r *http.Request, claims *auth.Claims) *http.Request {
	if claims == nil {
		return r
	}
	return r.WithContext(context.WithValue(r.Context(), middleware.UserContextKey, claims))
}

// reqWithParams pose des parametres de route chi (paires cle, valeur), comme
// si la requete avait traverse le routeur. Les appels successifs s'ajoutent
// au meme contexte de route.
func reqWithParams(r *http.Request, kv ...string) *http.Request {
	rctx, ok := r.Context().Value(chi.RouteCtxKey).(*chi.Context)
	if !ok {
		rctx = chi.NewRouteContext()
		r = r.WithContext(context.WithValue(r.Context(), chi.RouteCtxKey, rctx))
	}
	for i := 0; i+1 < len(kv); i += 2 {
		rctx.URLParams.Add(kv[i], kv[i+1])
	}
	return r
}

// wantErrorCode verifie le statut HTTP et le code d'erreur de l'enveloppe.
func wantErrorCode(t *testing.T, rec *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	if rec.Code != status {
		t.Fatalf("statut attendu %d, obtenu %d (corps: %s)", status, rec.Code, rec.Body.String())
	}
	var resp ErrorResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("corps d'erreur illisible: %v (corps: %s)", err, rec.Body.String())
	}
	if resp.Error.Code != code {
		t.Fatalf("code attendu %q, obtenu %q", code, resp.Error.Code)
	}
}

// waitUntil attend une condition sans sleep fixe, comme le waitFor de la
// suite du Hub.
func waitUntil(t *testing.T, timeout time.Duration, cond func() bool, msg string) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal(msg)
}

// --- faux ResponseWriter ---------------------------------------------------

// noFlushWriter masque le Flush du recorder : simule un serveur intermediaire
// qui ne sait pas streamer.
type noFlushWriter struct{ http.ResponseWriter }

// deadlineErrWriter fait echouer la pose de deadlines sur la connexion, avec
// une vraie erreur (pas le ErrNotSupported que setDeadlines tolere).
type deadlineErrWriter struct {
	http.ResponseWriter
	readErr, writeErr error
}

func (w deadlineErrWriter) SetReadDeadline(time.Time) error  { return w.readErr }
func (w deadlineErrWriter) SetWriteDeadline(time.Time) error { return w.writeErr }

// errBodyReader echoue apres un premier morceau : simule un diffuseur dont la
// connexion casse en plein direct.
type errBodyReader struct{ sent bool }

func (r *errBodyReader) Read(p []byte) (int, error) {
	if !r.sent {
		r.sent = true
		return copy(p, []byte("chunk")), nil
	}
	return 0, errInfra
}

// --- stubs de repositories -------------------------------------------------
// Chaque stub enveloppe le mock de testutil et ne fait echouer que la methode
// visee : le service au-dessus garde son comportement reel.

type stubStreamRepo struct {
	*testutil.MockStreamRepo
	createErr, findErr, listErr, updateErr, statusErr, listOwnerErr error
}

func (r *stubStreamRepo) Create(ctx context.Context, s *domain.Stream) error {
	if r.createErr != nil {
		return r.createErr
	}
	return r.MockStreamRepo.Create(ctx, s)
}

func (r *stubStreamRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Stream, error) {
	if r.findErr != nil {
		return nil, r.findErr
	}
	return r.MockStreamRepo.FindByID(ctx, id)
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

func (r *stubStreamRepo) ListByOwner(ctx context.Context, ownerID uuid.UUID) ([]domain.Stream, error) {
	if r.listOwnerErr != nil {
		return nil, r.listOwnerErr
	}
	return r.MockStreamRepo.ListByOwner(ctx, ownerID)
}

type stubPlaylistRepo struct {
	*testutil.MockPlaylistRepo
	createErr, findErr, listOwnerErr, updateErr, deleteErr, addErr, removeErr, reorderErr error
}

func (r *stubPlaylistRepo) Create(ctx context.Context, p *domain.Playlist) error {
	if r.createErr != nil {
		return r.createErr
	}
	return r.MockPlaylistRepo.Create(ctx, p)
}

func (r *stubPlaylistRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Playlist, error) {
	if r.findErr != nil {
		return nil, r.findErr
	}
	return r.MockPlaylistRepo.FindByID(ctx, id)
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

type stubMusicRepo struct {
	*testutil.MockMusicRepo
	createErr, findErr, listErr, searchErr, updateErr, deleteErr error
}

func (r *stubMusicRepo) Create(ctx context.Context, m *domain.Music) error {
	if r.createErr != nil {
		return r.createErr
	}
	return r.MockMusicRepo.Create(ctx, m)
}

func (r *stubMusicRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.Music, error) {
	if r.findErr != nil {
		return nil, r.findErr
	}
	return r.MockMusicRepo.FindByID(ctx, id)
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

type stubUserRepo struct {
	*testutil.MockUserRepo
	createErr, findErr, listErr, roleErr, deleteErr, profileErr error
}

func (r *stubUserRepo) Create(ctx context.Context, u *domain.User) error {
	if r.createErr != nil {
		return r.createErr
	}
	return r.MockUserRepo.Create(ctx, u)
}

func (r *stubUserRepo) FindByID(ctx context.Context, id uuid.UUID) (*domain.User, error) {
	if r.findErr != nil {
		return nil, r.findErr
	}
	return r.MockUserRepo.FindByID(ctx, id)
}

func (r *stubUserRepo) List(ctx context.Context, page, perPage int) ([]domain.User, int, error) {
	if r.listErr != nil {
		return nil, 0, r.listErr
	}
	return r.MockUserRepo.List(ctx, page, perPage)
}

func (r *stubUserRepo) UpdateRole(ctx context.Context, id uuid.UUID, role domain.Role) error {
	if r.roleErr != nil {
		return r.roleErr
	}
	return r.MockUserRepo.UpdateRole(ctx, id, role)
}

func (r *stubUserRepo) UpdateProfile(ctx context.Context, id uuid.UUID, email, username string) error {
	if r.profileErr != nil {
		return r.profileErr
	}
	return r.MockUserRepo.UpdateProfile(ctx, id, email, username)
}

func (r *stubUserRepo) Delete(ctx context.Context, id uuid.UUID) error {
	if r.deleteErr != nil {
		return r.deleteErr
	}
	return r.MockUserRepo.Delete(ctx, id)
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

// stubFavoriteRepo et stubMusicFavoriteRepo sont autonomes : testutil n'a pas
// de mock pour ces interfaces, et les handlers de favoris ne demandent que
// des reponses en conserve.
type stubFavoriteRepo struct {
	addErr, removeErr, listErr error
	streams                    []domain.Stream
}

func (r *stubFavoriteRepo) Add(context.Context, uuid.UUID, uuid.UUID) error    { return r.addErr }
func (r *stubFavoriteRepo) Remove(context.Context, uuid.UUID, uuid.UUID) error { return r.removeErr }
func (r *stubFavoriteRepo) ListByUser(context.Context, uuid.UUID, int, int) ([]domain.Stream, int, error) {
	if r.listErr != nil {
		return nil, 0, r.listErr
	}
	return r.streams, len(r.streams), nil
}
func (r *stubFavoriteRepo) Exists(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return false, nil
}

type stubMusicFavoriteRepo struct {
	addErr, removeErr, listErr, listIDsErr error
	tracks                                 []domain.Music
	ids                                    []uuid.UUID
}

func (r *stubMusicFavoriteRepo) Add(context.Context, uuid.UUID, uuid.UUID) error { return r.addErr }
func (r *stubMusicFavoriteRepo) Remove(context.Context, uuid.UUID, uuid.UUID) error {
	return r.removeErr
}
func (r *stubMusicFavoriteRepo) ListByUser(context.Context, uuid.UUID, int, int) ([]domain.Music, int, error) {
	if r.listErr != nil {
		return nil, 0, r.listErr
	}
	return r.tracks, len(r.tracks), nil
}
func (r *stubMusicFavoriteRepo) Exists(context.Context, uuid.UUID, uuid.UUID) (bool, error) {
	return false, nil
}
func (r *stubMusicFavoriteRepo) ListIDs(context.Context, uuid.UUID) ([]uuid.UUID, error) {
	if r.listIDsErr != nil {
		return nil, r.listIDsErr
	}
	return r.ids, nil
}

// --- deadlines -------------------------------------------------------------

// Quand la connexion refuse la pose de deadlines pour une vraie raison (pas
// un simple ErrNotSupported), l'erreur doit remonter, cote lecture comme
// cote ecriture, et keepConnectionOpen doit l'avaler sans paniquer.
func TestSetDeadlinesPropagatesControllerErrors(t *testing.T) {
	rec := httptest.NewRecorder()

	if err := setDeadlines(deadlineErrWriter{rec, errInfra, nil}, time.Time{}); !errors.Is(err, errInfra) {
		t.Fatalf("erreur de SetReadDeadline attendue, obtenu %v", err)
	}
	if err := setDeadlines(deadlineErrWriter{rec, nil, errInfra}, time.Time{}); !errors.Is(err, errInfra) {
		t.Fatalf("erreur de SetWriteDeadline attendue, obtenu %v", err)
	}

	keepConnectionOpen(deadlineErrWriter{rec, errInfra, nil}, zerolog.Nop())
}

// Garde-fou : les stubs doivent rester des implementations valides des
// interfaces du domaine.
var (
	_ domain.StreamRepository        = (*stubStreamRepo)(nil)
	_ domain.PlaylistRepository      = (*stubPlaylistRepo)(nil)
	_ domain.MusicRepository         = (*stubMusicRepo)(nil)
	_ domain.UserRepository          = (*stubUserRepo)(nil)
	_ domain.RefreshTokenRepository  = (*stubRefreshRepo)(nil)
	_ domain.FavoriteRepository      = (*stubFavoriteRepo)(nil)
	_ domain.MusicFavoriteRepository = (*stubMusicFavoriteRepo)(nil)
	_ io.Reader                      = (*errBodyReader)(nil)
)
