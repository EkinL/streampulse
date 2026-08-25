package http

import (
	nethttp "net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/rs/zerolog"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/internal/infrastructure/observability"
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
	jwtManager := auth.NewJWTManager("test-secret", time.Minute, time.Hour)

	// The router is built once for every case below: observability.NewMetrics
	// registers its collectors on the global Prometheus registry, so calling
	// it a second time in the same test binary would panic.
	router := NewRouter(RouterConfig{
		JWTManager:     jwtManager,
		Logger:         zerolog.Nop(),
		Metrics:        observability.NewMetrics(),
		CORSOrigins:    "*",
		RateLimitRPS:   1000,
		RateLimitBurst: 1000,
		ServiceName:    "test",
	})

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
