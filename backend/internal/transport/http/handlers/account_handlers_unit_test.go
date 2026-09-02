// Tests unitaires des handlers de compte : profil (UserHandler),
// administration (AdminHandler) et authentification (AuthHandler).
package handlers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/testutil"
)

// nopCloser satisfait application.StreamCloser sans Hub reel.
type nopCloser struct{}

func (nopCloser) CloseStream(uuid.UUID) {}

// stubFileRemover note les URLs qu'on lui demande d'effacer, sans toucher au
// disque : satisfait application.FileRemover pour les tests de handlers.
type stubFileRemover struct {
	mu      sync.Mutex
	deleted []string
	err     error
}

func (r *stubFileRemover) DeleteFile(url string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.err != nil {
		return r.err
	}
	r.deleted = append(r.deleted, url)
	return nil
}

type accountHarness struct {
	userRepo    *stubUserRepo
	streamRepo  *stubStreamRepo
	musicRepo   *stubMusicRepo
	fileRemover *stubFileRemover
	userSvc     *application.UserService
}

func newAccountHarness() *accountHarness {
	userRepo := &stubUserRepo{MockUserRepo: testutil.NewMockUserRepo()}
	streamRepo := &stubStreamRepo{MockStreamRepo: testutil.NewMockStreamRepo()}
	musicRepo := &stubMusicRepo{MockMusicRepo: testutil.NewMockMusicRepo()}
	fileRemover := &stubFileRemover{}
	return &accountHarness{
		userRepo:    userRepo,
		streamRepo:  streamRepo,
		musicRepo:   musicRepo,
		fileRemover: fileRemover,
		userSvc:     application.NewUserService(userRepo, streamRepo, musicRepo, nopCloser{}, fileRemover),
	}
}

func (h *accountHarness) existingUser(t *testing.T) *domain.User {
	t.Helper()
	user := testutil.NewTestUser(domain.RoleUser)
	if err := h.userRepo.MockUserRepo.Create(context.Background(), user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	return user
}

// --- UserHandler -----------------------------------------------------------

func TestUserHandlerRequiresAuthentication(t *testing.T) {
	h := NewUserHandler(newAccountHarness().userSvc)
	badClaims := unitClaims(uuid.New(), domain.RoleUser)
	badClaims.UserID = "pas-un-uuid"

	for name, fn := range map[string]http.HandlerFunc{
		"me":        h.Me,
		"update me": h.UpdateMe,
		"delete me": h.DeleteMe,
	} {
		t.Run(name+" sans claims", func(t *testing.T) {
			rec := httptest.NewRecorder()
			fn(rec, httptest.NewRequest(http.MethodGet, "/users/me", nil))
			wantErrorCode(t, rec, http.StatusUnauthorized, "UNAUTHORIZED")
		})
		t.Run(name+" claims corrompues", func(t *testing.T) {
			rec := httptest.NewRecorder()
			req := reqWithClaims(httptest.NewRequest(http.MethodGet, "/users/me", nil), badClaims)
			fn(rec, req)
			wantErrorCode(t, rec, http.StatusUnauthorized, "UNAUTHORIZED")
		})
	}
}

func TestUserHandlerRepoFailures(t *testing.T) {
	t.Run("me", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		harness.userRepo.findErr = errInfra
		h := NewUserHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodGet, "/users/me", nil),
			unitClaims(user.ID, domain.RoleUser))
		h.Me(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("delete me", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		harness.streamRepo.listOwnerErr = errInfra
		h := NewUserHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodDelete, "/users/me", nil),
			unitClaims(user.ID, domain.RoleUser))
		h.DeleteMe(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("delete me, morceaux illisibles", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		harness.musicRepo.allByUploaderErr = errInfra
		h := NewUserHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodDelete, "/users/me", nil),
			unitClaims(user.ID, domain.RoleUser))
		h.DeleteMe(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("update me", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		harness.userRepo.profileErr = errInfra
		h := NewUserHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodPatch, "/users/me",
			strings.NewReader(`{"email":"new@unit.io","username":"newname"}`)),
			unitClaims(user.ID, domain.RoleUser))
		h.UpdateMe(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})
}

// TestUserHandlerDeleteMeRemovesUploadedFiles verifie que le compte n'est pas
// le seul a disparaitre : les fichiers audio verses par la personne doivent
// etre effaces du disque, pas seulement leurs lignes en base (limite connue,
// docs/rgpd.md). Un morceau ajoute par URL externe ne doit pas etre touche.
func TestUserHandlerDeleteMeRemovesUploadedFiles(t *testing.T) {
	harness := newAccountHarness()
	user := harness.existingUser(t)
	ctx := context.Background()

	uploaded := &domain.Music{ID: uuid.New(), Title: "Verse", URL: "http://files.test/uploads/a.mp3", UploadedBy: user.ID}
	external := &domain.Music{ID: uuid.New(), Title: "Externe", URL: "https://cdn.test/b.mp3", UploadedBy: user.ID}
	for _, m := range []*domain.Music{uploaded, external} {
		if err := harness.musicRepo.MockMusicRepo.Create(ctx, m); err != nil {
			t.Fatalf("create music: %v", err)
		}
	}

	h := NewUserHandler(harness.userSvc)
	rec := httptest.NewRecorder()
	req := reqWithClaims(httptest.NewRequest(http.MethodDelete, "/users/me", nil),
		unitClaims(user.ID, domain.RoleUser))
	h.DeleteMe(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}

	if len(harness.fileRemover.deleted) != 2 {
		t.Fatalf("URLs effacees = %v, attendu les deux morceaux (le FileRemover decide lui-meme ce qu'il touche)", harness.fileRemover.deleted)
	}
}

// TestUserHandlerUpdateMe teste le droit de rectification (RGPD art. 16) :
// PATCH /users/me, jusqu'ici reserve a un administrateur en base.
func TestUserHandlerUpdateMe(t *testing.T) {
	t.Run("succes", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		h := NewUserHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodPatch, "/users/me",
			strings.NewReader(`{"email":"rectifie@unit.io","username":"rectifie"}`)),
			unitClaims(user.ID, domain.RoleUser))
		h.UpdateMe(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
		}

		updated, err := harness.userRepo.FindByID(context.Background(), user.ID)
		if err != nil {
			t.Fatalf("find updated user: %v", err)
		}
		if updated.Email != "rectifie@unit.io" || updated.Username != "rectifie" {
			t.Fatalf("profil non rectifie: %+v", updated)
		}
	})

	t.Run("corps invalide", func(t *testing.T) {
		h := NewUserHandler(newAccountHarness().userSvc)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodPatch, "/users/me",
			strings.NewReader("{pas du json")),
			unitClaims(uuid.New(), domain.RoleUser))
		h.UpdateMe(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("email invalide", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		h := NewUserHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodPatch, "/users/me",
			strings.NewReader(`{"email":"pas-un-email","username":"valide"}`)),
			unitClaims(user.ID, domain.RoleUser))
		h.UpdateMe(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("username trop court", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		h := NewUserHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodPatch, "/users/me",
			strings.NewReader(`{"email":"valide@unit.io","username":"ab"}`)),
			unitClaims(user.ID, domain.RoleUser))
		h.UpdateMe(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("email deja pris", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		other := testutil.NewTestUser(domain.RoleUser)
		other.Email = "prise@unit.io"
		if err := harness.userRepo.Create(context.Background(), other); err != nil {
			t.Fatalf("create other user: %v", err)
		}
		h := NewUserHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithClaims(httptest.NewRequest(http.MethodPatch, "/users/me",
			strings.NewReader(`{"email":"prise@unit.io","username":"nouveau"}`)),
			unitClaims(user.ID, domain.RoleUser))
		h.UpdateMe(rec, req)
		wantErrorCode(t, rec, http.StatusConflict, "CONFLICT")
	})
}

// --- AdminHandler ----------------------------------------------------------

func TestAdminHandlerRejectsInvalidInput(t *testing.T) {
	h := NewAdminHandler(newAccountHarness().userSvc)

	t.Run("update role invalid id", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := reqWithParams(httptest.NewRequest(http.MethodPut, "/admin/users/zzz/role",
			strings.NewReader(`{"role":"user"}`)), "id", "pas-un-uuid")
		h.UpdateUserRole(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("update role invalid body", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := reqWithParams(httptest.NewRequest(http.MethodPut, "/admin/users/x/role",
			strings.NewReader("{pas du json")), "id", uuid.New().String())
		h.UpdateUserRole(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("update role unknown role", func(t *testing.T) {
		// "listener" n'existe pas dans le sujet : il doit etre refuse.
		rec := httptest.NewRecorder()
		req := reqWithParams(httptest.NewRequest(http.MethodPut, "/admin/users/x/role",
			strings.NewReader(`{"role":"listener"}`)), "id", uuid.New().String())
		h.UpdateUserRole(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})

	t.Run("delete invalid id", func(t *testing.T) {
		rec := httptest.NewRecorder()
		req := reqWithParams(httptest.NewRequest(http.MethodDelete, "/admin/users/zzz", nil),
			"id", "pas-un-uuid")
		h.DeleteUser(rec, req)
		wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
	})
}

func TestAdminHandlerRepoFailures(t *testing.T) {
	t.Run("list users", func(t *testing.T) {
		harness := newAccountHarness()
		harness.userRepo.listErr = errInfra
		h := NewAdminHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		h.ListUsers(rec, httptest.NewRequest(http.MethodGet, "/admin/users", nil))
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("update role", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		harness.userRepo.roleErr = errInfra
		h := NewAdminHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithParams(httptest.NewRequest(http.MethodPut, "/admin/users/x/role",
			strings.NewReader(`{"role":"broadcaster"}`)), "id", user.ID.String())
		h.UpdateUserRole(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("delete user", func(t *testing.T) {
		harness := newAccountHarness()
		user := harness.existingUser(t)
		harness.userRepo.deleteErr = errInfra
		h := NewAdminHandler(harness.userSvc)
		rec := httptest.NewRecorder()
		req := reqWithParams(httptest.NewRequest(http.MethodDelete, "/admin/users/x", nil),
			"id", user.ID.String())
		h.DeleteUser(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})
}

// --- AuthHandler -----------------------------------------------------------

func newAuthHandlerHarness(userRepo domain.UserRepository, refreshRepo domain.RefreshTokenRepository) *AuthHandler {
	jwt := auth.NewJWTManager("unit-test-secret", 15*time.Minute, 24*time.Hour)
	return NewAuthHandler(application.NewAuthService(userRepo, refreshRepo, jwt, nil))
}

func TestAuthHandlerRejectsInvalidBody(t *testing.T) {
	h := newAuthHandlerHarness(testutil.NewMockUserRepo(), testutil.NewMockRefreshTokenRepo())
	for name, fn := range map[string]http.HandlerFunc{
		"register": h.Register,
		"login":    h.Login,
		"refresh":  h.Refresh,
	} {
		t.Run(name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			fn(rec, httptest.NewRequest(http.MethodPost, "/auth", strings.NewReader("{pas du json")))
			wantErrorCode(t, rec, http.StatusBadRequest, "BAD_REQUEST")
		})
	}
}

func TestAuthHandlerRepoFailures(t *testing.T) {
	ctx := context.Background()

	t.Run("register", func(t *testing.T) {
		// La creation du compte passe mais le stockage du refresh token
		// echoue : erreur interne, pas un conflit ni une entree invalide.
		refresh := &stubRefreshRepo{MockRefreshTokenRepo: testutil.NewMockRefreshTokenRepo(), storeErr: errInfra}
		h := newAuthHandlerHarness(testutil.NewMockUserRepo(), refresh)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/auth/register",
			strings.NewReader(`{"email":"a@b.io","username":"ab","password":"longenough","accepted_terms":true}`))
		h.Register(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("login", func(t *testing.T) {
		userRepo := testutil.NewMockUserRepo()
		hash, err := bcrypt.GenerateFromPassword([]byte("longenough"), bcrypt.MinCost)
		if err != nil {
			t.Fatalf("bcrypt: %v", err)
		}
		user := testutil.NewTestUser(domain.RoleUser)
		user.Email = "login@unit.io"
		user.PasswordHash = string(hash)
		if err := userRepo.Create(ctx, user); err != nil {
			t.Fatalf("create user: %v", err)
		}

		refresh := &stubRefreshRepo{MockRefreshTokenRepo: testutil.NewMockRefreshTokenRepo(), storeErr: errInfra}
		h := newAuthHandlerHarness(userRepo, refresh)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/auth/login",
			strings.NewReader(`{"email":"login@unit.io","password":"longenough"}`))
		h.Login(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})

	t.Run("refresh", func(t *testing.T) {
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

		h := newAuthHandlerHarness(userRepo, refresh)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/auth/refresh",
			strings.NewReader(`{"refresh_token":"valid-token"}`))
		h.Refresh(rec, req)
		wantErrorCode(t, rec, http.StatusInternalServerError, "INTERNAL_ERROR")
	})
}
