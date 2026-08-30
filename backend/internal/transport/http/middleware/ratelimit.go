package middleware

import (
	"net"
	"net/http"
	"strings"
	"sync"

	"golang.org/x/time/rate"
)

type RateLimiter struct {
	mu       sync.Mutex
	visitors map[string]*rate.Limiter
	rps      rate.Limit
	burst    int
	// trusted contient les reseaux dont on accepte les en-tetes de
	// transmission. Vide par defaut : voir clientKey.
	trusted []*net.IPNet
}

// NewRateLimiter construit le limiteur.
//
// trustedProxies liste les reverse-proxies de confiance, en CIDR
// ("10.0.0.0/8") ou en adresse simple ("192.168.1.10"). Laisser vide quand le
// serveur est expose directement : c'est le defaut, et c'est le reglage sur.
func NewRateLimiter(rps float64, burst int, trustedProxies ...string) *RateLimiter {
	return &RateLimiter{
		visitors: make(map[string]*rate.Limiter),
		rps:      rate.Limit(rps),
		burst:    burst,
		trusted:  parseCIDRs(trustedProxies),
	}
}

// parseCIDRs accepte des CIDR et des adresses simples. Une entree illisible
// est ignoree plutot que de faire echouer le demarrage : une faute de frappe
// dans TRUSTED_PROXIES doit retirer de la confiance, jamais en ajouter.
func parseCIDRs(entries []string) []*net.IPNet {
	nets := make([]*net.IPNet, 0, len(entries))
	for _, raw := range entries {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		if _, n, err := net.ParseCIDR(raw); err == nil {
			nets = append(nets, n)
			continue
		}
		if ip := net.ParseIP(raw); ip != nil {
			bits := 32
			if ip.To4() == nil {
				bits = 128
			}
			nets = append(nets, &net.IPNet{IP: ip, Mask: net.CIDRMask(bits, bits)})
		}
	}
	return nets
}

func (rl *RateLimiter) isTrusted(host string) bool {
	ip := net.ParseIP(host)
	if ip == nil {
		return false
	}
	for _, n := range rl.trusted {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

func (rl *RateLimiter) getLimiter(ip string) *rate.Limiter {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	limiter, exists := rl.visitors[ip]
	if !exists {
		limiter = rate.NewLimiter(rl.rps, rl.burst)
		rl.visitors[ip] = limiter
	}
	return limiter
}

// clientKey identifie le client a limiter.
//
// r.RemoteAddr vaut "IP:port" et le port source change a chaque connexion TCP :
// indexer dessus donnait un compteur neuf, avec son burst complet, a chaque
// requete (anomalie A-01 du cahier de recette). Seul l'hote compte.
//
// X-Forwarded-For n'est lu QUE si la connexion vient d'un proxy declare dans
// TRUSTED_PROXIES. C'est un en-tete que n'importe quel client peut ecrire : lui
// faire confiance sans condition permet d'obtenir un compteur vierge a chaque
// requete, ou de faire limiter un tiers en usurpant son adresse. C'est la
// raison pour laquelle chi a deprecie son middleware RealIP
// (GHSA-3fxj-6jh8-hvhx).
//
// Dans une chaine de plusieurs proxies, on parcourt X-Forwarded-For de droite
// a gauche : la premiere adresse qui n'est pas un proxy de confiance est le
// client. Tout ce qui se trouve a sa gauche a pu etre forge par lui.
func (rl *RateLimiter) clientKey(r *http.Request) string {
	host := r.RemoteAddr
	if h, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		host = h
	}

	if len(rl.trusted) == 0 || !rl.isTrusted(host) {
		return host
	}

	parts := strings.Split(r.Header.Get("X-Forwarded-For"), ",")
	for i := len(parts) - 1; i >= 0; i-- {
		candidate := strings.TrimSpace(parts[i])
		if candidate == "" {
			continue
		}
		if !rl.isTrusted(candidate) {
			return candidate
		}
	}
	return host
}

func (rl *RateLimiter) Limit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		limiter := rl.getLimiter(rl.clientKey(r))
		if !limiter.Allow() {
			http.Error(w, `{"error":{"code":"RATE_LIMITED","message":"too many requests"}}`, http.StatusTooManyRequests)
			return
		}

		next.ServeHTTP(w, r)
	})
}
