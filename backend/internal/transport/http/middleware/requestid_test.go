package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	chimiddleware "github.com/go-chi/chi/v5/middleware"
)

func TestRequestIDHeaderIsExposedToClient(t *testing.T) {
	var seenInContext string
	handler := chimiddleware.RequestID(RequestIDHeader(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			seenInContext = chimiddleware.GetReqID(r.Context())
			w.WriteHeader(http.StatusOK)
		})))

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))

	header := rec.Header().Get(RequestIDHeaderName)
	if header == "" {
		t.Fatalf("header %s absent de la reponse", RequestIDHeaderName)
	}
	if header != seenInContext {
		t.Errorf("le header (%s) differe de l'identifiant du contexte (%s)", header, seenInContext)
	}
}

// TestRequestIDHeaderSetBeforeResponse : un header pose apres WriteHeader est
// ignore. Le middleware doit donc l'ecrire avant de passer la main, y compris
// quand le handler suivant repond immediatement.
func TestRequestIDHeaderSetBeforeResponse(t *testing.T) {
	handler := chimiddleware.RequestID(RequestIDHeader(http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, `{"error":{"code":"UNAUTHORIZED"}}`, http.StatusUnauthorized)
		})))

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/playlists", nil))

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", rec.Code)
	}
	// C'est precisement le cas qui n'avait aucun identifiant exploitable : les
	// erreurs ecrites par http.Error n'ont pas d'enveloppe meta.
	if rec.Header().Get(RequestIDHeaderName) == "" {
		t.Errorf("header %s absent d'une reponse d'erreur middleware", RequestIDHeaderName)
	}
}

func TestRequestIDHeaderNoopWithoutChiMiddleware(t *testing.T) {
	handler := RequestIDHeader(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))

	if got := rec.Header().Get(RequestIDHeaderName); got != "" {
		t.Errorf("sans chimiddleware.RequestID le header doit rester absent, got %q", got)
	}
}
