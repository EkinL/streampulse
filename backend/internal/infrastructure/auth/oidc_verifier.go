package auth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/streampulse/backend/internal/domain"
)

// Points d'entree JWKS publics des fournisseurs. Ce sont des constantes du
// protocole OpenID Connect, pas de la configuration de deploiement : seules
// les audiences acceptees viennent des variables d'env.
const (
	googleJWKSURL = "https://www.googleapis.com/oauth2/v3/certs"
	appleJWKSURL  = "https://appleid.apple.com/auth/keys"
)

// jwksCacheTTL borne la duree de vie des cles en cache ; jwksRetryDelay evite
// de marteler le fournisseur quand un token arrive avec un kid inconnu.
const (
	jwksCacheTTL   = time.Hour
	jwksRetryDelay = time.Minute
)

// OIDCProvider decrit un fournisseur d'identite : ou chercher ses cles de
// signature, quels emetteurs et quelles audiences (client IDs) accepter.
type OIDCProvider struct {
	Name      string
	JWKSURL   string
	Issuers   []string
	Audiences []string
}

// GoogleProvider accepte les ID tokens Google Sign-In. Google emet "iss"
// avec ou sans schema selon la plateforme, d'ou les deux valeurs.
func GoogleProvider(audiences []string) OIDCProvider {
	return OIDCProvider{
		Name:      domain.ProviderGoogle,
		JWKSURL:   googleJWKSURL,
		Issuers:   []string{"https://accounts.google.com", "accounts.google.com"},
		Audiences: audiences,
	}
}

// AppleProvider accepte les identity tokens de Sign in with Apple.
func AppleProvider(audiences []string) OIDCProvider {
	return OIDCProvider{
		Name:      domain.ProviderApple,
		JWKSURL:   appleJWKSURL,
		Issuers:   []string{"https://appleid.apple.com"},
		Audiences: audiences,
	}
}

// OIDCVerifier implemente domain.OAuthVerifier : il verifie la signature
// d'un ID token contre le JWKS du fournisseur (cles RSA mises en cache),
// puis l'emetteur, l'audience et l'expiration.
type OIDCVerifier struct {
	providers map[string]OIDCProvider
	client    *http.Client

	mu    sync.Mutex
	cache map[string]*jwksEntry
}

type jwksEntry struct {
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}

var _ domain.OAuthVerifier = (*OIDCVerifier)(nil)

func NewOIDCVerifier(providers ...OIDCProvider) *OIDCVerifier {
	m := make(map[string]OIDCProvider, len(providers))
	for _, p := range providers {
		m[p.Name] = p
	}
	return &OIDCVerifier{
		providers: m,
		client:    &http.Client{Timeout: 10 * time.Second},
		cache:     make(map[string]*jwksEntry),
	}
}

func (v *OIDCVerifier) Verify(ctx context.Context, provider, idToken string) (*domain.OAuthIdentity, error) {
	p, ok := v.providers[provider]
	if !ok {
		return nil, fmt.Errorf("oidc: verify: unknown provider %q: %w", provider, domain.ErrInvalidInput)
	}
	// Aucune audience configuree = fournisseur desactive sur ce deploiement.
	if len(p.Audiences) == 0 {
		return nil, fmt.Errorf("oidc: verify: %s: %w", provider, domain.ErrProviderNotConfigured)
	}

	claims := jwt.MapClaims{}
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithExpirationRequired(),
		jwt.WithIssuedAt(),
	)
	_, err := parser.ParseWithClaims(idToken, claims, func(token *jwt.Token) (interface{}, error) {
		kid, _ := token.Header["kid"].(string)
		if kid == "" {
			return nil, fmt.Errorf("oidc: token has no kid header")
		}
		return v.keyFor(ctx, p, kid)
	})
	if err != nil {
		return nil, fmt.Errorf("oidc: verify %s token: %v: %w", provider, err, domain.ErrTokenInvalid)
	}

	issuer, err := claims.GetIssuer()
	if err != nil || !containsString(p.Issuers, issuer) {
		return nil, fmt.Errorf("oidc: verify %s token: unexpected issuer %q: %w", provider, issuer, domain.ErrTokenInvalid)
	}
	audiences, err := claims.GetAudience()
	if err != nil || !intersects(p.Audiences, audiences) {
		return nil, fmt.Errorf("oidc: verify %s token: audience mismatch: %w", provider, domain.ErrTokenInvalid)
	}
	subject, err := claims.GetSubject()
	if err != nil || subject == "" {
		return nil, fmt.Errorf("oidc: verify %s token: missing subject: %w", provider, domain.ErrTokenInvalid)
	}

	email, _ := claims["email"].(string)
	name, _ := claims["name"].(string)
	return &domain.OAuthIdentity{
		Provider:      provider,
		Subject:       subject,
		Email:         email,
		EmailVerified: boolClaim(claims["email_verified"]),
		Name:          name,
	}, nil
}

// keyFor rend la cle publique du kid demande, en rechargeant le JWKS quand
// le cache est vide, perime, ou ne connait pas ce kid (rotation de cles).
func (v *OIDCVerifier) keyFor(ctx context.Context, p OIDCProvider, kid string) (*rsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()

	entry := v.cache[p.Name]
	needsFetch := entry == nil ||
		time.Since(entry.fetchedAt) > jwksCacheTTL ||
		(entry.keys[kid] == nil && time.Since(entry.fetchedAt) > jwksRetryDelay)
	if needsFetch {
		keys, err := v.fetchJWKS(ctx, p.JWKSURL)
		if err != nil {
			return nil, err
		}
		entry = &jwksEntry{keys: keys, fetchedAt: time.Now()}
		v.cache[p.Name] = entry
	}

	key, ok := entry.keys[kid]
	if !ok {
		return nil, fmt.Errorf("oidc: no key for kid %q at %s", kid, p.JWKSURL)
	}
	return key, nil
}

func (v *OIDCVerifier) fetchJWKS(ctx context.Context, url string) (map[string]*rsa.PublicKey, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("oidc: fetch jwks: %w", err)
	}
	resp, err := v.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("oidc: fetch jwks: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("oidc: fetch jwks: %s returned %d", url, resp.StatusCode)
	}

	var doc struct {
		Keys []struct {
			Kty string `json:"kty"`
			Kid string `json:"kid"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&doc); err != nil {
		return nil, fmt.Errorf("oidc: decode jwks: %w", err)
	}

	keys := make(map[string]*rsa.PublicKey, len(doc.Keys))
	for _, k := range doc.Keys {
		if k.Kty != "RSA" || k.Kid == "" {
			continue
		}
		pub, err := rsaKeyFromJWK(k.N, k.E)
		if err != nil {
			return nil, fmt.Errorf("oidc: jwks key %s: %w", k.Kid, err)
		}
		keys[k.Kid] = pub
	}
	return keys, nil
}

func rsaKeyFromJWK(n, e string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(n)
	if err != nil {
		return nil, fmt.Errorf("decode modulus: %w", err)
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(e)
	if err != nil {
		return nil, fmt.Errorf("decode exponent: %w", err)
	}
	eInt := new(big.Int).SetBytes(eBytes)
	if !eInt.IsInt64() || eInt.Int64() <= 0 {
		return nil, fmt.Errorf("invalid exponent")
	}
	return &rsa.PublicKey{N: new(big.Int).SetBytes(nBytes), E: int(eInt.Int64())}, nil
}

// boolClaim tolere les deux encodages rencontres : bool chez Google,
// parfois la chaine "true" chez Apple.
func boolClaim(v interface{}) bool {
	switch t := v.(type) {
	case bool:
		return t
	case string:
		return t == "true"
	}
	return false
}

func containsString(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

func intersects(allowed, got []string) bool {
	for _, g := range got {
		if containsString(allowed, g) {
			return true
		}
	}
	return false
}
