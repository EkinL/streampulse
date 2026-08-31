package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func preflight(handler http.Handler, origin string) http.Header {
	req := httptest.NewRequest(http.MethodOptions, "/playlists", nil)
	req.Header.Set("Origin", origin)
	req.Header.Set("Access-Control-Request-Method", http.MethodPost)
	req.Header.Set("Access-Control-Request-Headers", "Authorization")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec.Header()
}

func TestCORSAllowsConfiguredOriginsOnly(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	handler := CORSHandler("https://app.streampulse.test, https://console.streampulse.test").Handler(next)

	for _, origin := range []string{"https://app.streampulse.test", "https://console.streampulse.test"} {
		h := preflight(handler, origin)
		if got := h.Get("Access-Control-Allow-Origin"); got != origin {
			t.Errorf("origine %s : Allow-Origin = %q", origin, got)
		}
		if h.Get("Access-Control-Allow-Methods") == "" {
			t.Errorf("origine %s : pas de methodes autorisees dans le preflight", origin)
		}
	}

	if got := preflight(handler, "https://evil.test").Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("origine inconnue acceptee: Allow-Origin = %q", got)
	}
}

func TestCORSExposesRequestID(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	handler := CORSHandler("*").Handler(next)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.Header.Set("Origin", "https://anywhere.test")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if got := rec.Header().Get("Access-Control-Expose-Headers"); got == "" {
		t.Fatal("X-Request-ID doit etre expose au navigateur pour la correlation des logs")
	}
}

// TestCORSCredentialsOnlyWithNamedOrigins : `Allow-Origin: *` avec
// `Allow-Credentials: true` est une paire que les navigateurs rejettent
// (observation O-3). Le joker n'annonce donc plus les credentials ; une
// origine nommee, si.
func TestCORSCredentialsOnlyWithNamedOrigins(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })

	h := preflight(CORSHandler("*").Handler(next), "https://anywhere.test")
	if got := h.Get("Access-Control-Allow-Origin"); got != "*" {
		t.Errorf("joker : Allow-Origin = %q, attendu *", got)
	}
	if got := h.Get("Access-Control-Allow-Credentials"); got != "" {
		t.Errorf("joker : Allow-Credentials = %q, ne doit pas etre annonce", got)
	}

	h = preflight(CORSHandler("https://console.streampulse.test").Handler(next), "https://console.streampulse.test")
	if got := h.Get("Access-Control-Allow-Credentials"); got != "true" {
		t.Errorf("origine nommee : Allow-Credentials = %q, attendu true", got)
	}
}
