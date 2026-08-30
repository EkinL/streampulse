package handlers

import (
	"bytes"
	"context"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/filestore"
	"github.com/streampulse/backend/testutil"
)

type musicHarness struct {
	handler    *MusicHandler
	repo       *stubMusicRepo
	streamRepo *stubStreamRepo
}

func newMusicHarness(t *testing.T) *musicHarness {
	t.Helper()
	repo := &stubMusicRepo{MockMusicRepo: testutil.NewMockMusicRepo()}
	streamRepo := &stubStreamRepo{MockStreamRepo: testutil.NewMockStreamRepo()}
	store := filestore.NewFileStore(t.TempDir(), "http://files.test/uploads")
	svc := application.NewMusicService(repo, store)
	return &musicHarness{
		handler:    NewMusicHandler(svc, streamRepo),
		repo:       repo,
		streamRepo: streamRepo,
	}
}

func (h *musicHarness) ownedMusic(t *testing.T, uploaderID uuid.UUID) *domain.Music {
	t.Helper()
	music := &domain.Music{Title: "t", Artist: "a", URL: "http://x/y.mp3", UploadedBy: uploaderID}
	if err := h.repo.MockMusicRepo.Create(context.Background(), music); err != nil {
		t.Fatalf("create music: %v", err)
	}
	return music
}

// multipartUpload construit un corps multipart avec un champ file et un titre.
func multipartUpload(t *testing.T) (*bytes.Buffer, string) {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	part, err := w.CreateFormFile("file", "song.mp3")
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	if _, err := part.Write([]byte("audio")); err != nil {
		t.Fatalf("write part: %v", err)
	}
	if err := w.WriteField("title", "Titre"); err != nil {
		t.Fatalf("write field: %v", err)
	}
	if err := w.Close(); err != nil {
		t.Fatalf("close writer: %v", err)
	}
	return &buf, w.FormDataContentType()
}

func TestMusicHandlerRequiresAuthentication(t *testing.T) {
	h := newMusicHarness(t)
	cases := map[string]http.HandlerFunc{
		"upload": h.handler.UploadMusic,
		"update": h.handler.UpdateMusic,
		"delete": h.handler.DeleteMusic,
	}
	for name, fn := range cases {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			fn(rec, httptest.NewRequest(http.MethodPost, "/music", strings.NewReader("{}")))
			wantErrorCode(t, rec, http.StatusUnauthorized, "UNAUTHORIZED")
		})
	}

	// Des claims corrompues (user_id illisible) valent une absence de session.
	badClaims := unitClaims(uuid.New(), domain.RoleBroadcaster)
	badClaims.UserID = "pas-un-uuid"
	for name, fn := range cases {
		t.Run(name+" claims corrompues", func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPost, "/music", strings.NewReader("{}"))
			fn(rec, reqWithClaims(req, badClaims))
			wantErrorCode(t, rec, http.StatusUnauthorized, "UNAUTHORIZED")
		})
	}
}

func TestMusicHandlerRejectsInvalidInput(t *testing.T) {
	h := newMusicHarness(t)
	claims := unitClaims(uuid.New(), domain.RoleBroadcaster)

	t.Run("get invalid id", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := reqWithParams(httptest.NewRequest(http.MethodGet, "/music/zzz", nil), "id", "pas-un-uuid")
		h.handler.GetMusic(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "INVALID_ID")
	})

	for name, fn := range map[string]http.HandlerFunc{
		"update": h.handler.UpdateMusic,
		"delete": h.handler.DeleteMusic,
	} {
		t.Run(name+" invalid id", func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodPut, "/music/zzz", strings.NewReader("{}"))
			req = reqWithClaims(req, claims)
			req = reqWithParams(req, "id", "pas-un-uuid")
			fn(rec, req)
			wantErrorCode(t, rec, http.StatusBadRequest, "INVALID_ID")
		})
	}

	t.Run("upload json invalid body", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/music", strings.NewReader("{pas du json"))
		req.Header.Set("Content-Type", "application/json")
		h.handler.UploadMusic(rec, reqWithClaims(req, claims))
		wantErrorCode(t, rec, http.StatusBadRequest, "INVALID_BODY")
	})

	t.Run("upload multipart invalid body", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/music", strings.NewReader("pas du multipart"))
		req.Header.Set("Content-Type", "multipart/form-data; boundary=xyz")
		h.handler.UploadMusic(rec, reqWithClaims(req, claims))
		wantErrorCode(t, rec, http.StatusBadRequest, "INVALID_BODY")
	})

	t.Run("update invalid body", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPut, "/music/x", strings.NewReader("{pas du json"))
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "id", uuid.New().String())
		h.handler.UpdateMusic(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("search without query", func(t *testing.T) {
		rec := httptest.NewRecorder()
		h.handler.SearchMusic(rec, httptest.NewRequest(http.MethodGet, "/music/search", nil))
		wantErrorCode(t, rec, http.StatusBadRequest, "INVALID_INPUT")
	})
}

// L'upload multipart doit pouvoir repousser les deadlines de la connexion ;
// si la connexion refuse, on ne lit pas 32 Mo pour rien.
func TestMusicHandlerUploadFailsWhenDeadlinesCannotBeExtended(t *testing.T) {
	h := newMusicHarness(t)
	body, contentType := multipartUpload(t)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/music", body)
	req.Header.Set("Content-Type", contentType)
	req = reqWithClaims(req, unitClaims(uuid.New(), domain.RoleBroadcaster))

	h.handler.UploadMusic(deadlineErrWriter{rec, errInfra, nil}, req)
	wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
}

func TestMusicHandlerRepoFailures(t *testing.T) {
	uploaderID := uuid.New()
	claims := unitClaims(uploaderID, domain.RoleBroadcaster)

	t.Run("list", func(t *testing.T) {
		h := newMusicHarness(t)
		h.repo.listErr = errInfra
		rec := httptest.NewRecorder()
		h.handler.ListMusic(rec, httptest.NewRequest(http.MethodGet, "/music", nil))
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("get", func(t *testing.T) {
		h := newMusicHarness(t)
		h.repo.findErr = errInfra
		rec := httptest.NewRecorder()
		req := reqWithParams(httptest.NewRequest(http.MethodGet, "/music/x", nil), "id", uuid.New().String())
		h.handler.GetMusic(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("search", func(t *testing.T) {
		h := newMusicHarness(t)
		h.repo.searchErr = errInfra
		rec := httptest.NewRecorder()
		h.handler.SearchMusic(rec, httptest.NewRequest(http.MethodGet, "/music/search?q=x", nil))
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("upload json create", func(t *testing.T) {
		h := newMusicHarness(t)
		h.repo.createErr = errInfra
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/music",
			strings.NewReader(`{"title":"t","url":"http://x/y.mp3"}`))
		req.Header.Set("Content-Type", "application/json")
		h.handler.UploadMusic(rec, reqWithClaims(req, claims))
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("upload multipart create", func(t *testing.T) {
		h := newMusicHarness(t)
		h.repo.createErr = errInfra
		body, contentType := multipartUpload(t)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/music", body)
		req.Header.Set("Content-Type", contentType)
		h.handler.UploadMusic(rec, reqWithClaims(req, claims))
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("update", func(t *testing.T) {
		h := newMusicHarness(t)
		music := h.ownedMusic(t, uploaderID)
		h.repo.updateErr = errInfra
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPut, "/music/x", strings.NewReader(`{"title":"t2"}`))
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "id", music.ID.String())
		h.handler.UpdateMusic(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("delete", func(t *testing.T) {
		h := newMusicHarness(t)
		music := h.ownedMusic(t, uploaderID)
		h.repo.deleteErr = errInfra
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodDelete, "/music/x", nil)
		req = reqWithClaims(req, claims)
		req = reqWithParams(req, "id", music.ID.String())
		h.handler.DeleteMusic(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("global search music", func(t *testing.T) {
		h := newMusicHarness(t)
		h.repo.searchErr = errInfra
		rec := httptest.NewRecorder()
		h.handler.GlobalSearch(rec, httptest.NewRequest(http.MethodGet, "/search?q=x", nil))
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("global search streams", func(t *testing.T) {
		h := newMusicHarness(t)
		h.streamRepo.listErr = errInfra
		rec := httptest.NewRecorder()
		h.handler.GlobalSearch(rec, httptest.NewRequest(http.MethodGet, "/search?q=x", nil))
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})
}

func TestMusicHandlerGlobalSearchWithoutQuery(t *testing.T) {
	h := newMusicHarness(t)
	rec := httptest.NewRecorder()
	h.handler.GlobalSearch(rec, httptest.NewRequest(http.MethodGet, "/search", nil))
	wantErrorCode(t, rec, http.StatusBadRequest, "INVALID_INPUT")
}
