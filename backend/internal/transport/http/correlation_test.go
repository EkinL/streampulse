package http

import (
	"encoding/json"
	nethttp "net/http"
	"net/http/httptest"
	"testing"

	"github.com/streampulse/backend/internal/transport/http/middleware"
)

// TestRequestIDIsCorrelatedEndToEnd est le test qui porte le critere : un seul
// identifiant doit relier ce que voit le client et ce que voient les logs.
//
// Avant ce travail il y en avait trois, sans rapport entre eux :
// chimiddleware.RequestID (dans le contexte, jamais expose), un uuid neuf
// genere par reponse dans meta.requestId, et le trace id OTEL absent des logs.
// Un utilisateur citant son meta.requestId n'etait retrouvable nulle part.
func TestRequestIDIsCorrelatedEndToEnd(t *testing.T) {
	router, _ := testRouter(t)

	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, httptest.NewRequest(nethttp.MethodGet, "/health", nil))

	if rec.Code != nethttp.StatusOK {
		t.Fatalf("status %d, want 200", rec.Code)
	}

	header := rec.Header().Get(middleware.RequestIDHeaderName)
	if header == "" {
		t.Fatalf("header %s absent de la reponse", middleware.RequestIDHeaderName)
	}

	var body struct {
		Meta struct {
			RequestID string `json:"requestId"`
		} `json:"meta"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("corps illisible: %v", err)
	}

	if body.Meta.RequestID != header {
		t.Errorf("meta.requestId (%s) et le header %s (%s) doivent etre le meme identifiant",
			body.Meta.RequestID, middleware.RequestIDHeaderName, header)
	}
}

// TestRequestIDReachesMiddlewareErrors : les 401/403/429 sont ecrits par
// http.Error et n'ont pas d'enveloppe meta. Le header est leur seul
// identifiant exploitable.
func TestRequestIDReachesMiddlewareErrors(t *testing.T) {
	router, _ := testRouter(t)

	for _, path := range []string{"/playlists", "/metrics", "/admin/users"} {
		t.Run(path, func(t *testing.T) {
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, httptest.NewRequest(nethttp.MethodGet, path, nil))

			if rec.Code != nethttp.StatusUnauthorized {
				t.Fatalf("status %d, want 401", rec.Code)
			}
			if rec.Header().Get(middleware.RequestIDHeaderName) == "" {
				t.Errorf("header %s absent : cette erreur n'est correlable a aucun log",
					middleware.RequestIDHeaderName)
			}
		})
	}
}

// TestRequestIDsAreDistinctPerRequest : un identifiant reutilise ne correle
// plus rien.
func TestRequestIDsAreDistinctPerRequest(t *testing.T) {
	router, _ := testRouter(t)

	seen := make(map[string]bool)
	for i := 0; i < 5; i++ {
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, httptest.NewRequest(nethttp.MethodGet, "/health", nil))

		id := rec.Header().Get(middleware.RequestIDHeaderName)
		if seen[id] {
			t.Fatalf("identifiant %q reutilise entre deux requetes", id)
		}
		seen[id] = true
	}
}
