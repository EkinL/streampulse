package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/streampulse/backend/internal/infrastructure/auth"
)

type contextKey string

const UserContextKey contextKey = "user"

type AuthMiddleware struct {
	jwt *auth.JWTManager
}

func NewAuthMiddleware(jwt *auth.JWTManager) *AuthMiddleware {
	return &AuthMiddleware{jwt: jwt}
}

func (m *AuthMiddleware) Authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if header == "" {
			http.Error(w, `{"error":{"code":"UNAUTHORIZED","message":"missing authorization header"}}`, http.StatusUnauthorized)
			return
		}

		parts := strings.SplitN(header, " ", 2)
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			http.Error(w, `{"error":{"code":"UNAUTHORIZED","message":"invalid authorization format"}}`, http.StatusUnauthorized)
			return
		}

		claims, err := m.jwt.ValidateToken(parts[1])
		if err != nil {
			http.Error(w, `{"error":{"code":"UNAUTHORIZED","message":"invalid or expired token"}}`, http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(r.Context(), UserContextKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// AuthenticateWebSocket authentifie comme Authenticate, mais accepte aussi le
// token dans le parametre de requete `token`. L'API WebSocket des navigateurs
// ne permet pas de poser un header Authorization sur la poignee de main ; le
// client mobile, lui, garde le header classique.
func (m *AuthMiddleware) AuthenticateWebSocket(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := ""
		if header := r.Header.Get("Authorization"); header != "" {
			parts := strings.SplitN(header, " ", 2)
			if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
				http.Error(w, `{"error":{"code":"UNAUTHORIZED","message":"invalid authorization format"}}`, http.StatusUnauthorized)
				return
			}
			token = parts[1]
		} else {
			token = r.URL.Query().Get("token")
		}
		if token == "" {
			http.Error(w, `{"error":{"code":"UNAUTHORIZED","message":"missing authorization header"}}`, http.StatusUnauthorized)
			return
		}

		claims, err := m.jwt.ValidateToken(token)
		if err != nil {
			http.Error(w, `{"error":{"code":"UNAUTHORIZED","message":"invalid or expired token"}}`, http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(r.Context(), UserContextKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func GetClaims(ctx context.Context) *auth.Claims {
	claims, ok := ctx.Value(UserContextKey).(*auth.Claims)
	if !ok {
		return nil
	}
	return claims
}
