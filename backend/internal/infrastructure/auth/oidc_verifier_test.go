package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/streampulse/backend/internal/domain"
)

// jwksTestServer sert un JWKS contenant la cle publique de key sous le kid
// donne, comme le feraient Google ou Apple.
func jwksTestServer(t *testing.T, kid string, key *rsa.PrivateKey) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		doc := map[string]interface{}{
			"keys": []map[string]string{{
				"kty": "RSA",
				"kid": kid,
				"alg": "RS256",
				"use": "sig",
				"n":   base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
				"e":   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes()),
			}},
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(doc)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func signIDToken(t *testing.T, key *rsa.PrivateKey, kid string, claims jwt.MapClaims) string {
	t.Helper()
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = kid
	signed, err := token.SignedString(key)
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return signed
}

func googleClaims(overrides map[string]interface{}) jwt.MapClaims {
	claims := jwt.MapClaims{
		"iss":            "https://accounts.google.com",
		"aud":            "client-id-1",
		"sub":            "sub-42",
		"email":          "alice@example.com",
		"email_verified": true,
		"name":           "Alice",
		"iat":            time.Now().Add(-time.Minute).Unix(),
		"exp":            time.Now().Add(time.Hour).Unix(),
	}
	for k, v := range overrides {
		claims[k] = v
	}
	return claims
}

func testVerifier(srv *httptest.Server) *OIDCVerifier {
	return NewOIDCVerifier(OIDCProvider{
		Name:      domain.ProviderGoogle,
		JWKSURL:   srv.URL,
		Issuers:   []string{"https://accounts.google.com", "accounts.google.com"},
		Audiences: []string{"client-id-1", "client-id-2"},
	})
}

func TestOIDCVerifier_Verify(t *testing.T) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	srv := jwksTestServer(t, "kid-1", key)
	ctx := context.Background()

	t.Run("valid token", func(t *testing.T) {
		v := testVerifier(srv)
		token := signIDToken(t, key, "kid-1", googleClaims(nil))

		identity, err := v.Verify(ctx, domain.ProviderGoogle, token)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if identity.Subject != "sub-42" || identity.Email != "alice@example.com" || !identity.EmailVerified || identity.Name != "Alice" {
			t.Fatalf("unexpected identity: %+v", identity)
		}
		if identity.Provider != domain.ProviderGoogle {
			t.Fatalf("unexpected provider %s", identity.Provider)
		}
	})

	t.Run("email_verified as string, apple style", func(t *testing.T) {
		v := testVerifier(srv)
		token := signIDToken(t, key, "kid-1", googleClaims(map[string]interface{}{"email_verified": "true"}))

		identity, err := v.Verify(ctx, domain.ProviderGoogle, token)
		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if !identity.EmailVerified {
			t.Fatal("expected email to count as verified")
		}
	})

	t.Run("wrong audience", func(t *testing.T) {
		v := testVerifier(srv)
		token := signIDToken(t, key, "kid-1", googleClaims(map[string]interface{}{"aud": "someone-else"}))

		if _, err := v.Verify(ctx, domain.ProviderGoogle, token); !errors.Is(err, domain.ErrTokenInvalid) {
			t.Fatalf("expected ErrTokenInvalid, got %v", err)
		}
	})

	t.Run("wrong issuer", func(t *testing.T) {
		v := testVerifier(srv)
		token := signIDToken(t, key, "kid-1", googleClaims(map[string]interface{}{"iss": "https://evil.example.com"}))

		if _, err := v.Verify(ctx, domain.ProviderGoogle, token); !errors.Is(err, domain.ErrTokenInvalid) {
			t.Fatalf("expected ErrTokenInvalid, got %v", err)
		}
	})

	t.Run("expired token", func(t *testing.T) {
		v := testVerifier(srv)
		token := signIDToken(t, key, "kid-1", googleClaims(map[string]interface{}{"exp": time.Now().Add(-time.Hour).Unix()}))

		if _, err := v.Verify(ctx, domain.ProviderGoogle, token); !errors.Is(err, domain.ErrTokenInvalid) {
			t.Fatalf("expected ErrTokenInvalid, got %v", err)
		}
	})

	t.Run("token signed by another key", func(t *testing.T) {
		otherKey, err := rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			t.Fatalf("generate key: %v", err)
		}
		v := testVerifier(srv)
		token := signIDToken(t, otherKey, "kid-1", googleClaims(nil))

		if _, err := v.Verify(ctx, domain.ProviderGoogle, token); !errors.Is(err, domain.ErrTokenInvalid) {
			t.Fatalf("expected ErrTokenInvalid, got %v", err)
		}
	})

	t.Run("alg none is rejected", func(t *testing.T) {
		v := testVerifier(srv)
		token := jwt.NewWithClaims(jwt.SigningMethodNone, googleClaims(nil))
		token.Header["kid"] = "kid-1"
		raw, err := token.SignedString(jwt.UnsafeAllowNoneSignatureType)
		if err != nil {
			t.Fatalf("sign: %v", err)
		}

		if _, err := v.Verify(ctx, domain.ProviderGoogle, raw); !errors.Is(err, domain.ErrTokenInvalid) {
			t.Fatalf("expected ErrTokenInvalid, got %v", err)
		}
	})

	t.Run("unknown provider", func(t *testing.T) {
		v := testVerifier(srv)
		if _, err := v.Verify(ctx, "facebook", "whatever"); !errors.Is(err, domain.ErrInvalidInput) {
			t.Fatalf("expected ErrInvalidInput, got %v", err)
		}
	})

	t.Run("provider without audience is not configured", func(t *testing.T) {
		v := NewOIDCVerifier(OIDCProvider{
			Name:    domain.ProviderApple,
			JWKSURL: srv.URL,
			Issuers: []string{"https://appleid.apple.com"},
		})
		if _, err := v.Verify(ctx, domain.ProviderApple, "whatever"); !errors.Is(err, domain.ErrProviderNotConfigured) {
			t.Fatalf("expected ErrProviderNotConfigured, got %v", err)
		}
	})

	t.Run("jwks is cached between calls", func(t *testing.T) {
		calls := 0
		counting := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			calls++
			doc := map[string]interface{}{
				"keys": []map[string]string{{
					"kty": "RSA",
					"kid": "kid-1",
					"n":   base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
					"e":   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes()),
				}},
			}
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(doc)
		}))
		defer counting.Close()

		v := testVerifier(counting)
		token := signIDToken(t, key, "kid-1", googleClaims(nil))
		for i := 0; i < 3; i++ {
			if _, err := v.Verify(ctx, domain.ProviderGoogle, token); err != nil {
				t.Fatalf("verify %d: %v", i, err)
			}
		}
		if calls != 1 {
			t.Fatalf("expected a single JWKS fetch, got %d", calls)
		}
	})
}
