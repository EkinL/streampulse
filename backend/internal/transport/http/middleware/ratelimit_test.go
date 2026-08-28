package middleware

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func hit(handler http.Handler, remoteAddr, forwardedFor string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	req.RemoteAddr = remoteAddr
	if forwardedFor != "" {
		req.Header.Set("X-Forwarded-For", forwardedFor)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
}

func TestRateLimiterBurstThenReject(t *testing.T) {
	handler := NewRateLimiter(1, 2).Limit(okHandler())

	for i := 1; i <= 2; i++ {
		if rec := hit(handler, "10.0.0.1:40001", ""); rec.Code != http.StatusOK {
			t.Fatalf("requete %d dans le burst: status %d", i, rec.Code)
		}
	}
	rec := hit(handler, "10.0.0.1:40001", "")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("3e requete: status %d, attendu 429", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"RATE_LIMITED"`) {
		t.Errorf("corps sans code RATE_LIMITED: %s", rec.Body.String())
	}
}

// Anomalie A-01 du cahier de recette : le port source change a chaque
// connexion TCP. Deux connexions du meme hote doivent partager le compteur,
// sinon la limite n'est jamais atteinte.
func TestRateLimiterKeyIgnoresSourcePort(t *testing.T) {
	handler := NewRateLimiter(1, 1).Limit(okHandler())

	if rec := hit(handler, "10.0.0.1:40001", ""); rec.Code != http.StatusOK {
		t.Fatalf("premiere connexion: status %d", rec.Code)
	}
	if rec := hit(handler, "10.0.0.1:40002", ""); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("meme hote, autre port: status %d, attendu 429", rec.Code)
	}
	if rec := hit(handler, "10.0.0.2:40001", ""); rec.Code != http.StatusOK {
		t.Fatalf("autre hote: status %d, attendu 200 (compteur separe)", rec.Code)
	}
}

func TestRateLimiterHonoursForwardedFor(t *testing.T) {
	handler := NewRateLimiter(1, 1).Limit(okHandler())

	if rec := hit(handler, "10.0.0.1:40001", "203.0.113.9"); rec.Code != http.StatusOK {
		t.Fatalf("client A via proxy: status %d", rec.Code)
	}
	if rec := hit(handler, "10.0.0.1:40001", "203.0.113.9"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("client A rejoue: status %d, attendu 429", rec.Code)
	}
	if rec := hit(handler, "10.0.0.1:40001", "203.0.113.10"); rec.Code != http.StatusOK {
		t.Fatalf("client B derriere le meme proxy: status %d, attendu 200", rec.Code)
	}
}

func TestRateLimiterRefills(t *testing.T) {
	// 200 req/s : un jeton revient toutes les 5 ms.
	handler := NewRateLimiter(200, 1).Limit(okHandler())

	if rec := hit(handler, "10.0.0.1:1", ""); rec.Code != http.StatusOK {
		t.Fatalf("premiere requete: status %d", rec.Code)
	}
	if rec := hit(handler, "10.0.0.1:1", ""); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("burst epuise: status %d, attendu 429", rec.Code)
	}
	time.Sleep(20 * time.Millisecond)
	if rec := hit(handler, "10.0.0.1:1", ""); rec.Code != http.StatusOK {
		t.Fatalf("apres recharge: status %d, attendu 200", rec.Code)
	}
}
