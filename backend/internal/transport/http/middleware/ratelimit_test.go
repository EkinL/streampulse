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

// Derriere un proxy DECLARE de confiance, X-Forwarded-For identifie le client :
// deux clients distincts derriere le meme proxy ont des compteurs separes.
func TestRateLimiterHonoursForwardedForFromTrustedProxy(t *testing.T) {
	handler := NewRateLimiter(1, 1, "10.0.0.1").Limit(okHandler())

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

// Le test de securite : sans proxy declare, X-Forwarded-For est ignore.
//
// Le faire suivre sans condition permettrait a n'importe quel client d'obtenir
// un compteur vierge en changeant l'en-tete a chaque requete, ce qui annule la
// limite. C'est la faille pour laquelle chi a deprecie RealIP
// (GHSA-3fxj-6jh8-hvhx).
func TestRateLimiterIgnoresForwardedForFromUntrustedPeer(t *testing.T) {
	handler := NewRateLimiter(1, 1).Limit(okHandler())

	if rec := hit(handler, "10.0.0.1:40001", "203.0.113.9"); rec.Code != http.StatusOK {
		t.Fatalf("premiere requete: status %d", rec.Code)
	}
	// Meme pair, en-tete different : le compteur doit rester le meme.
	if rec := hit(handler, "10.0.0.1:40002", "203.0.113.10"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("X-Forwarded-For forge: status %d, attendu 429 (compteur partage)", rec.Code)
	}
	if rec := hit(handler, "10.0.0.1:40003", "198.51.100.1"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("autre en-tete forge: status %d, attendu 429", rec.Code)
	}
}

// Un pair non declare ne gagne pas de confiance parce qu'il pretend etre le
// proxy : c'est l'adresse de connexion qui decide, pas l'en-tete.
func TestRateLimiterTrustIsBasedOnPeerNotHeader(t *testing.T) {
	handler := NewRateLimiter(1, 1, "10.0.0.1").Limit(okHandler())

	if rec := hit(handler, "198.51.100.7:40001", "203.0.113.9"); rec.Code != http.StatusOK {
		t.Fatalf("premiere requete: status %d", rec.Code)
	}
	if rec := hit(handler, "198.51.100.7:40002", "203.0.113.10"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("pair non declare: status %d, attendu 429", rec.Code)
	}
}

// Chaine de proxies : on remonte de droite a gauche jusqu'a la premiere
// adresse non declaree. Tout ce qui est a sa gauche a pu etre forge par elle.
func TestRateLimiterWalksProxyChainRightToLeft(t *testing.T) {
	handler := NewRateLimiter(1, 1, "10.0.0.0/8").Limit(okHandler())

	// "1.2.3.4" est forge par le client ; le vrai client est 203.0.113.9,
	// derniere adresse non declaree avant les deux proxies internes.
	if rec := hit(handler, "10.0.0.1:40001", "1.2.3.4, 203.0.113.9, 10.0.0.9"); rec.Code != http.StatusOK {
		t.Fatalf("premiere requete: status %d", rec.Code)
	}
	// Meme client reel, prefixe forge different : compteur partage.
	if rec := hit(handler, "10.0.0.1:40002", "9.9.9.9, 203.0.113.9, 10.0.0.9"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("prefixe forge: status %d, attendu 429", rec.Code)
	}
	if rec := hit(handler, "10.0.0.1:40003", "1.2.3.4, 203.0.113.20, 10.0.0.9"); rec.Code != http.StatusOK {
		t.Fatalf("autre client reel: status %d, attendu 200", rec.Code)
	}
}

// Une entree illisible dans TRUSTED_PROXIES doit retirer de la confiance,
// jamais en ajouter.
func TestRateLimiterIgnoresMalformedTrustedEntries(t *testing.T) {
	handler := NewRateLimiter(1, 1, "pas-une-adresse", "").Limit(okHandler())

	if rec := hit(handler, "10.0.0.1:40001", "203.0.113.9"); rec.Code != http.StatusOK {
		t.Fatalf("premiere requete: status %d", rec.Code)
	}
	if rec := hit(handler, "10.0.0.1:40002", "203.0.113.10"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("status %d, attendu 429 : aucune confiance ne doit etre accordee", rec.Code)
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
