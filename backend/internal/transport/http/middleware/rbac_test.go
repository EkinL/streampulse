package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
)

func requestAs(role domain.Role) *http.Request {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	if role == "" {
		return req
	}
	ctx := context.WithValue(req.Context(), UserContextKey, &auth.Claims{Role: role})
	return req.WithContext(ctx)
}

// La hierarchie des roles est le coeur de l'autorisation : chaque role doit
// passer exactement les seuils inferieurs ou egaux au sien, et aucun autre.
func TestRequireRoleMatrix(t *testing.T) {
	roles := []domain.Role{domain.RoleAnonymous, domain.RoleUser, domain.RoleBroadcaster, domain.RoleAdmin}
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })

	for _, min := range roles {
		handler := RequireRole(min)(next)
		for _, have := range roles {
			t.Run(string(have)+" vers seuil "+string(min), func(t *testing.T) {
				rec := httptest.NewRecorder()
				handler.ServeHTTP(rec, requestAs(have))

				want := http.StatusForbidden
				if have.AtLeast(min) {
					want = http.StatusOK
				}
				if rec.Code != want {
					t.Fatalf("status %d, attendu %d", rec.Code, want)
				}
				if want == http.StatusForbidden && !strings.Contains(rec.Body.String(), `"FORBIDDEN"`) {
					t.Errorf("corps sans code FORBIDDEN: %s", rec.Body.String())
				}
			})
		}
	}
}

func TestRequireRoleWithoutClaims(t *testing.T) {
	handler := RequireRole(domain.RoleUser)(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		t.Fatal("le handler ne doit pas etre atteint sans claims")
	}))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, requestAs(""))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, attendu 401", rec.Code)
	}
}

// Un role inconnu (jeton forge avec "role":"superuser") ne doit jamais passer
// un seuil, meme le plus bas.
func TestRequireRoleRejectsUnknownRole(t *testing.T) {
	handler := RequireRole(domain.RoleAnonymous)(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, requestAs(domain.Role("superuser")))
	if rec.Code != http.StatusForbidden {
		t.Fatalf("status %d, attendu 403", rec.Code)
	}
}
