package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/testutil"
)

type playlistHarness struct {
	handler *PlaylistHandler
	repo    *stubPlaylistRepo
}

func newPlaylistHarness() *playlistHarness {
	repo := &stubPlaylistRepo{MockPlaylistRepo: testutil.NewMockPlaylistRepo()}
	return &playlistHarness{
		handler: NewPlaylistHandler(application.NewPlaylistService(repo)),
		repo:    repo,
	}
}

func (h *playlistHarness) ownedPlaylist(t *testing.T, ownerID uuid.UUID) *domain.Playlist {
	t.Helper()
	playlist := testutil.NewTestPlaylist(ownerID)
	if err := h.repo.MockPlaylistRepo.Create(context.Background(), playlist); err != nil {
		t.Fatalf("create playlist: %v", err)
	}
	return playlist
}

func TestPlaylistHandlerRequiresAuthentication(t *testing.T) {
	h := newPlaylistHarness()
	cases := map[string]http.HandlerFunc{
		"list":    h.handler.ListPlaylists,
		"create":  h.handler.CreatePlaylist,
		"get":     h.handler.GetPlaylist,
		"update":  h.handler.UpdatePlaylist,
		"delete":  h.handler.DeletePlaylist,
		"add":     h.handler.AddTrack,
		"reorder": h.handler.ReorderTracks,
		"remove":  h.handler.RemoveTrack,
	}
	for name, fn := range cases {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			fn(rec, httptest.NewRequest(http.MethodGet, "/playlists", strings.NewReader("{}")))
			wantErrorCode(t, rec, http.StatusUnauthorized, "UNAUTHORIZED")
		})
	}
}

func TestPlaylistHandlerRejectsInvalidID(t *testing.T) {
	h := newPlaylistHarness()
	claims := unitClaims(uuid.New(), domain.RoleUser)
	cases := map[string]http.HandlerFunc{
		"get":     h.handler.GetPlaylist,
		"update":  h.handler.UpdatePlaylist,
		"delete":  h.handler.DeletePlaylist,
		"add":     h.handler.AddTrack,
		"reorder": h.handler.ReorderTracks,
		"remove":  h.handler.RemoveTrack,
	}
	for name, fn := range cases {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodGet, "/playlists/zzz", strings.NewReader("{}"))
			req = reqWithClaims(req, claims)
			req = reqWithParams(req, "id", "pas-un-uuid")
			fn(rec, req)
			wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
		})
	}

	t.Run("remove track id", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodDelete, "/playlists/x/tracks/zzz", nil)
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "id", uuid.New().String(), "trackId", "pas-un-uuid")
		h.handler.RemoveTrack(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})
}

func TestPlaylistHandlerRejectsInvalidBody(t *testing.T) {
	h := newPlaylistHarness()
	ownerID := uuid.New()
	claims := unitClaims(ownerID, domain.RoleUser)
	playlist := h.ownedPlaylist(t, ownerID)

	cases := map[string]http.HandlerFunc{
		"create":  h.handler.CreatePlaylist,
		"update":  h.handler.UpdatePlaylist,
		"add":     h.handler.AddTrack,
		"reorder": h.handler.ReorderTracks,
	}
	for name, fn := range cases {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, "/playlists", strings.NewReader("{pas du json"))
			req = reqWithClaims(req, claims)
			req = reqWithParams(req, "id", playlist.ID.String())
			fn(rec, req)
			wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
		})
	}

	t.Run("reorder invalid track id", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPut, "/playlists/x/tracks/reorder",
			strings.NewReader(`{"track_ids":["pas-un-uuid"]}`))
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "id", playlist.ID.String())
		h.handler.ReorderTracks(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})
}

func TestPlaylistHandlerUpdateUnknownPlaylist(t *testing.T) {
	h := newPlaylistHarness()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPut, "/playlists/x", strings.NewReader(`{"name":"n"}`))
	req = reqWithClaims(req, unitClaims(uuid.New(), domain.RoleUser))
	req = reqWithParams(req, "id", uuid.New().String())
	h.handler.UpdatePlaylist(rec, req)
	wantErrorCode(t, rec, http.StatusNotFound, "NOT_FOUND")
}

func TestPlaylistHandlerRepoFailures(t *testing.T) {
	ownerID := uuid.New()
	claims := unitClaims(ownerID, domain.RoleUser)

	cases := map[string]struct {
		mutate  func(*stubPlaylistRepo)
		request func(*playlistHarness) (*http.Request, http.HandlerFunc)
	}{
		"list": {
			mutate: func(r *stubPlaylistRepo) { r.listOwnerErr = errInfra },
			request: func(h *playlistHarness) (*http.Request, http.HandlerFunc) {
				return httptest.NewRequest(http.MethodGet, "/playlists", nil), h.handler.ListPlaylists
			},
		},
		"create": {
			mutate: func(r *stubPlaylistRepo) { r.createErr = errInfra },
			request: func(h *playlistHarness) (*http.Request, http.HandlerFunc) {
				req := httptest.NewRequest(http.MethodPost, "/playlists", strings.NewReader(`{"name":"n"}`))
				return req, h.handler.CreatePlaylist
			},
		},
		"get": {
			mutate: func(r *stubPlaylistRepo) { r.findErr = errInfra },
			request: func(h *playlistHarness) (*http.Request, http.HandlerFunc) {
				req := httptest.NewRequest(http.MethodGet, "/playlists/x", nil)
				return reqWithParams(req, "id", uuid.New().String()), h.handler.GetPlaylist
			},
		},
		"update": {
			mutate: func(r *stubPlaylistRepo) { r.updateErr = errInfra },
			request: func(h *playlistHarness) (*http.Request, http.HandlerFunc) {
				req := httptest.NewRequest(http.MethodPut, "/playlists/x", strings.NewReader(`{"name":"n"}`))
				return req, h.handler.UpdatePlaylist
			},
		},
		"delete": {
			mutate: func(r *stubPlaylistRepo) { r.deleteErr = errInfra },
			request: func(h *playlistHarness) (*http.Request, http.HandlerFunc) {
				return httptest.NewRequest(http.MethodDelete, "/playlists/x", nil), h.handler.DeletePlaylist
			},
		},
		"add track": {
			mutate: func(r *stubPlaylistRepo) { r.addErr = errInfra },
			request: func(h *playlistHarness) (*http.Request, http.HandlerFunc) {
				req := httptest.NewRequest(http.MethodPost, "/playlists/x/tracks",
					strings.NewReader(`{"title":"t","url":"u"}`))
				return req, h.handler.AddTrack
			},
		},
		"reorder": {
			mutate: func(r *stubPlaylistRepo) { r.reorderErr = errInfra },
			request: func(h *playlistHarness) (*http.Request, http.HandlerFunc) {
				req := httptest.NewRequest(http.MethodPut, "/playlists/x/tracks/reorder",
					strings.NewReader(`{"track_ids":["`+uuid.New().String()+`"]}`))
				return req, h.handler.ReorderTracks
			},
		},
		"remove track": {
			mutate: func(r *stubPlaylistRepo) { r.removeErr = errInfra },
			request: func(h *playlistHarness) (*http.Request, http.HandlerFunc) {
				req := httptest.NewRequest(http.MethodDelete, "/playlists/x/tracks/y", nil)
				return reqWithParams(req, "trackId", uuid.New().String()), h.handler.RemoveTrack
			},
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			h := newPlaylistHarness()
			playlist := h.ownedPlaylist(t, ownerID)
			tc.mutate(h.repo)
			req, fn := tc.request(h)
			req = reqWithClaims(req, claims)
			req = reqWithParams(req, "id", playlist.ID.String())
			rec := httptest.NewRecorder()
			fn(rec, req)
			wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
		})
	}
}
