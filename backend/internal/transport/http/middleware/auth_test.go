package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
)

func TestAuthenticate(t *testing.T) {
	jwtManager := auth.NewJWTManager("mw-secret", time.Minute, time.Hour)
	user := &domain.User{ID: uuid.New(), Email: "u@test.local", Username: "u", Role: domain.RoleUser}
	pair, err := jwtManager.GenerateTokenPair(user)
	if err != nil {
		t.Fatalf("GenerateTokenPair: %v", err)
	}
	expiredPair, err := auth.NewJWTManager("mw-secret", -time.Minute, time.Hour).GenerateTokenPair(user)
	if err != nil {
		t.Fatalf("GenerateTokenPair (expire): %v", err)
	}

	var seen *auth.Claims
	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = GetClaims(r.Context())
		w.WriteHeader(http.StatusOK)
	})
	handler := NewAuthMiddleware(jwtManager).Authenticate(next)

	tests := []struct {
		name       string
		header     string
		wantStatus int
	}{
		{"sans en-tete", "", http.StatusUnauthorized},
		{"schema Basic", "Basic dXNlcjpwYXNz", http.StatusUnauthorized},
		{"Bearer sans jeton", "Bearer", http.StatusUnauthorized},
		{"jeton illisible", "Bearer not-a-jwt", http.StatusUnauthorized},
		{"jeton expire", "Bearer " + expiredPair.AccessToken, http.StatusUnauthorized},
		{"jeton valide", "Bearer " + pair.AccessToken, http.StatusOK},
		{"schema insensible a la casse", "bearer " + pair.AccessToken, http.StatusOK},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			seen = nil
			req := httptest.NewRequest(http.MethodGet, "/", nil)
			if tt.header != "" {
				req.Header.Set("Authorization", tt.header)
			}
			rec := httptest.NewRecorder()
			handler.ServeHTTP(rec, req)

			if rec.Code != tt.wantStatus {
				t.Fatalf("status %d, attendu %d", rec.Code, tt.wantStatus)
			}
			if tt.wantStatus == http.StatusUnauthorized {
				if !strings.Contains(rec.Body.String(), `"UNAUTHORIZED"`) {
					t.Errorf("corps sans code UNAUTHORIZED: %s", rec.Body.String())
				}
				if seen != nil {
					t.Error("le handler suivant ne doit pas etre appele")
				}
				return
			}
			if seen == nil || seen.UserID != user.ID.String() || seen.Role != domain.RoleUser {
				t.Errorf("claims transmises au handler: %+v", seen)
			}
		})
	}
}

func TestGetClaimsWithoutAuthentication(t *testing.T) {
	if GetClaims(context.Background()) != nil {
		t.Fatal("sans authentification, GetClaims doit rendre nil")
	}
}
