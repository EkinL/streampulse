package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/testutil"
)

func TestFavoritesHandlerRequiresAuthentication(t *testing.T) {
	h := NewFavoritesHandler(&stubFavoriteRepo{}, testutil.NewMockStreamRepo())
	cases := map[string]http.HandlerFunc{
		"list":   h.ListFavorites,
		"add":    h.AddFavorite,
		"remove": h.RemoveFavorite,
	}
	for name, fn := range cases {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			fn(rec, httptest.NewRequest(http.MethodGet, "/users/me/favorites", nil))
			wantErrorCode(t, rec, http.StatusUnauthorized, "UNAUTHORIZED")
		})
	}
}

func TestFavoritesHandlerRejectsInvalidStreamID(t *testing.T) {
	h := NewFavoritesHandler(&stubFavoriteRepo{}, testutil.NewMockStreamRepo())
	claims := unitClaims(uuid.New(), domain.RoleUser)
	for name, fn := range map[string]http.HandlerFunc{
		"add":    h.AddFavorite,
		"remove": h.RemoveFavorite,
	} {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, "/users/me/favorites/zzz", nil)
			req = reqWithClaims(req, claims)
			req = reqWithParams(req, "streamId", "pas-un-uuid")
			fn(rec, req)
			wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
		})
	}
}

func TestFavoritesHandlerRepoFailures(t *testing.T) {
	claims := unitClaims(uuid.New(), domain.RoleUser)
	streamRepo := testutil.NewMockStreamRepo()
	stream := testutil.NewTestStream(uuid.New())
	if err := streamRepo.Create(context.Background(), stream); err != nil {
		t.Fatalf("create stream: %v", err)
	}

	t.Run("list", func(t *testing.T) {
		h := NewFavoritesHandler(&stubFavoriteRepo{listErr: errInfra}, streamRepo)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodGet, "/users/me/favorites", nil), claims)
		h.ListFavorites(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("add check stream", func(t *testing.T) {
		// La verification d'existence echoue pour une autre raison qu'un
		// flux inconnu.
		h := NewFavoritesHandler(&stubFavoriteRepo{},
			&stubStreamRepo{MockStreamRepo: streamRepo, findErr: errInfra})
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/users/me/favorites/x", nil)
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "streamId", stream.ID.String())
		h.AddFavorite(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("add", func(t *testing.T) {
		h := NewFavoritesHandler(&stubFavoriteRepo{addErr: errInfra}, streamRepo)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/users/me/favorites/x", nil)
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "streamId", stream.ID.String())
		h.AddFavorite(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("remove", func(t *testing.T) {
		h := NewFavoritesHandler(&stubFavoriteRepo{removeErr: errInfra}, streamRepo)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodDelete, "/users/me/favorites/x", nil)
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "streamId", stream.ID.String())
		h.RemoveFavorite(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})
}

func TestMusicFavoritesHandlerRequiresAuthentication(t *testing.T) {
	h := NewMusicFavoritesHandler(&stubMusicFavoriteRepo{}, testutil.NewMockMusicRepo())
	cases := map[string]http.HandlerFunc{
		"list":     h.ListFavorites,
		"list ids": h.ListFavoriteIDs,
		"add":      h.AddFavorite,
		"remove":   h.RemoveFavorite,
	}
	for name, fn := range cases {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			fn(rec, httptest.NewRequest(http.MethodGet, "/users/me/favorites/music", nil))
			wantErrorCode(t, rec, http.StatusUnauthorized, "UNAUTHORIZED")
		})
	}
}

func TestMusicFavoritesHandlerRejectsInvalidMusicID(t *testing.T) {
	h := NewMusicFavoritesHandler(&stubMusicFavoriteRepo{}, testutil.NewMockMusicRepo())
	claims := unitClaims(uuid.New(), domain.RoleUser)
	for name, fn := range map[string]http.HandlerFunc{
		"add":    h.AddFavorite,
		"remove": h.RemoveFavorite,
	} {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, "/users/me/favorites/music/zzz", nil)
			req = reqWithClaims(req, claims)
			req = reqWithParams(req, "id", "pas-un-uuid")
			fn(rec, req)
			wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
		})
	}
}

func TestMusicFavoritesHandlerRepoFailures(t *testing.T) {
	claims := unitClaims(uuid.New(), domain.RoleUser)
	musicRepo := testutil.NewMockMusicRepo()
	music := &domain.Music{Title: "t", UploadedBy: uuid.New()}
	if err := musicRepo.Create(context.Background(), music); err != nil {
		t.Fatalf("create music: %v", err)
	}

	t.Run("list", func(t *testing.T) {
		h := NewMusicFavoritesHandler(&stubMusicFavoriteRepo{listErr: errInfra}, musicRepo)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodGet, "/users/me/favorites/music", nil), claims)
		h.ListFavorites(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("list ids", func(t *testing.T) {
		h := NewMusicFavoritesHandler(&stubMusicFavoriteRepo{listIDsErr: errInfra}, musicRepo)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodGet, "/users/me/favorites/music/ids", nil), claims)
		h.ListFavoriteIDs(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("add check music", func(t *testing.T) {
		h := NewMusicFavoritesHandler(&stubMusicFavoriteRepo{},
			&stubMusicRepo{MockMusicRepo: musicRepo, findErr: errInfra})
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/users/me/favorites/music/x", nil)
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "id", music.ID.String())
		h.AddFavorite(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("add", func(t *testing.T) {
		h := NewMusicFavoritesHandler(&stubMusicFavoriteRepo{addErr: errInfra}, musicRepo)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/users/me/favorites/music/x", nil)
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "id", music.ID.String())
		h.AddFavorite(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("remove", func(t *testing.T) {
		h := NewMusicFavoritesHandler(&stubMusicFavoriteRepo{removeErr: errInfra}, musicRepo)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodDelete, "/users/me/favorites/music/x", nil)
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "id", music.ID.String())
		h.RemoveFavorite(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})
}

// Le listing des identifiants favoris rend un tableau de chaines, meme vide.
func TestMusicFavoritesHandlerListIDs(t *testing.T) {
	id := uuid.New()
	h := NewMusicFavoritesHandler(&stubMusicFavoriteRepo{ids: []uuid.UUID{id}}, testutil.NewMockMusicRepo())
	rec := httptest.NewRecorder()
	req := reqWithClaims(httptest.NewRequest(http.MethodGet, "/users/me/favorites/music/ids", nil),
		unitClaims(uuid.New(), domain.RoleUser))
	h.ListFavoriteIDs(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("statut attendu 200, obtenu %d (corps: %s)", rec.Code, rec.Body.String())
	}
	if body := rec.Body.String(); !strings.Contains(body, id.String()) {
		t.Fatalf("l'identifiant %s manque dans la reponse: %s", id, body)
	}
}
