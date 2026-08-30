package http

import (
	nethttp "net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
)

func testToken(t *testing.T, m *auth.JWTManager, role domain.Role) string {
	t.Helper()
	pair, err := m.GenerateTokenPair(&domain.User{
		ID:       uuid.New(),
		Email:    string(role) + "@test.local",
		Username: string(role),
		Role:     role,
	})
	if err != nil {
		t.Fatalf("generate token pair: %v", err)
	}
	return pair.AccessToken
}

func TestMetricsAccess(t *testing.T) {
	// Shared with the rest of the package: observability.NewMetrics registers
	// its collectors on the global Prometheus registry, so building a second
	// router in the same test binary would panic. See testRouter in
	// openapi_test.go.
	router, jwtManager := testRouter(t)

	tests := []struct {
		name       string
		path       string
		token      string
		wantStatus int
	}{
		{"health stays public", "/health", "", nethttp.StatusOK},
		{"metrics without token", "/metrics", "", nethttp.StatusUnauthorized},
		{"metrics with user token", "/metrics", testToken(t, jwtManager, domain.RoleUser), nethttp.StatusForbidden},
		{"metrics with broadcaster token", "/metrics", testToken(t, jwtManager, domain.RoleBroadcaster), nethttp.StatusForbidden},
		{"metrics with admin token", "/metrics", testToken(t, jwtManager, domain.RoleAdmin), nethttp.StatusOK},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(nethttp.MethodGet, tt.path, nil)
			if tt.token != "" {
				req.Header.Set("Authorization", "Bearer "+tt.token)
			}
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != tt.wantStatus {
				t.Fatalf("GET %s: got status %d, want %d", tt.path, rec.Code, tt.wantStatus)
			}
			if tt.path == "/metrics" && tt.wantStatus == nethttp.StatusOK &&
				!strings.Contains(rec.Body.String(), "active_streams") {
				t.Fatalf("admin /metrics response does not look like Prometheus output")
			}
		})
	}
}
