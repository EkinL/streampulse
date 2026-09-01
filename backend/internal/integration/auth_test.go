package integration_test

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
)

// UC-01 / UC-02 / UC-03 : inscription, connexion, rafraichissement.
func TestAuth_RegisterLoginRefresh(t *testing.T) {
	s := newSuite(t)
	email := uniqueEmail("alice")

	r := s.do(t, http.MethodPost, "/auth/register", "", map[string]any{
		"email": email, "username": "alice", "password": password, "accepted_terms": true,
	}).expect(t, http.StatusCreated, "")
	d := r.data(t)
	user, _ := d["user"].(map[string]any)
	if str(d, "access_token") == "" || str(d, "refresh_token") == "" {
		t.Fatalf("l'inscription doit emettre les deux jetons: %s", r.Raw)
	}
	if str(user, "role") != string(domain.RoleUser) || str(user, "email") != email {
		t.Fatalf("utilisateur inattendu: %v", user)
	}
	if _, leaked := user["password"]; leaked {
		t.Fatal("le mot de passe ne doit jamais figurer dans une reponse")
	}
	if _, leaked := user["password_hash"]; leaked {
		t.Fatal("le hash ne doit jamais figurer dans une reponse")
	}
	firstRefresh := str(d, "refresh_token")

	s.do(t, http.MethodPost, "/auth/login", "", map[string]any{
		"email": email, "password": "mauvais-mot-de-passe",
	}).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")

	s.do(t, http.MethodPost, "/auth/login", "", map[string]any{
		"email": "inconnu@it.test", "password": password,
	}).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")

	_, secondRefresh := s.login(t, email)

	// Une connexion revoque les refresh tokens precedents.
	s.do(t, http.MethodPost, "/auth/refresh", "", map[string]any{"refresh_token": firstRefresh}).
		expect(t, http.StatusUnauthorized, "UNAUTHORIZED")

	// Rotation : le jeton presente est consomme et remplace.
	d = s.do(t, http.MethodPost, "/auth/refresh", "", map[string]any{"refresh_token": secondRefresh}).
		expect(t, http.StatusOK, "").data(t)
	thirdAccess, thirdRefresh := str(d, "access_token"), str(d, "refresh_token")
	if thirdRefresh == "" || thirdRefresh == secondRefresh {
		t.Fatal("le rafraichissement doit emettre un nouveau refresh token")
	}

	// Rejeu du jeton consomme : usage unique.
	s.do(t, http.MethodPost, "/auth/refresh", "", map[string]any{"refresh_token": secondRefresh}).
		expect(t, http.StatusUnauthorized, "UNAUTHORIZED")

	// Le nouveau jeton d'acces ouvre bien les routes authentifiees.
	s.do(t, http.MethodGet, "/playlists", thirdAccess, nil).expect(t, http.StatusOK, "")
}

func TestAuth_RegisterValidation(t *testing.T) {
	s := newSuite(t)
	taken := s.register(t, domain.RoleUser)

	cases := []struct {
		name   string
		body   any
		status int
		code   string
	}{
		{"mot de passe absent", map[string]any{"email": uniqueEmail("v"), "username": "v"}, http.StatusBadRequest, "BAD_REQUEST"},
		{"mot de passe trop court", map[string]any{"email": uniqueEmail("v"), "username": "v", "password": "1234567"}, http.StatusBadRequest, "BAD_REQUEST"},
		{"email vide", map[string]any{"email": "", "username": "v", "password": password}, http.StatusBadRequest, "BAD_REQUEST"},
		{"JSON malforme", "{", http.StatusBadRequest, "BAD_REQUEST"},
		// Mass assignment : un champ inconnu est refuse, on ne peut pas
		// s'auto-attribuer un role a l'inscription.
		{"champ inconnu (role)", map[string]any{"email": uniqueEmail("v"), "username": "v", "password": password, "role": "admin"}, http.StatusBadRequest, "BAD_REQUEST"},
		{"conditions d'utilisation non acceptees", map[string]any{"email": uniqueEmail("v"), "username": "v", "password": password}, http.StatusBadRequest, "BAD_REQUEST"},
		{"email deja pris", map[string]any{"email": taken.Email, "username": "autre", "password": password, "accepted_terms": true}, http.StatusConflict, "CONFLICT"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s.do(t, http.MethodPost, "/auth/register", "", tc.body).expect(t, tc.status, tc.code)
		})
	}
}

// Le mot de passe est stocke en bcrypt, jamais en clair, et le refresh token
// est stocke hache : la base ne contient aucun secret directement utilisable.
func TestAuth_SecretsAreStoredHashed(t *testing.T) {
	s := newSuite(t)
	acc := s.register(t, domain.RoleUser)
	ctx := context.Background()

	stored, err := s.users.FindByEmail(ctx, acc.Email)
	if err != nil {
		t.Fatalf("FindByEmail: %v", err)
	}
	if !strings.HasPrefix(stored.PasswordHash, "$2a$12$") {
		t.Fatalf("hash bcrypt (cout 12) attendu, obtenu %q", stored.PasswordHash)
	}
	if strings.Contains(stored.PasswordHash, password) {
		t.Fatal("le mot de passe apparait en clair dans le hash")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(stored.PasswordHash), []byte(password)); err != nil {
		t.Fatalf("le hash ne correspond pas au mot de passe: %v", err)
	}

	var tokenHash string
	err = s.pool.QueryRow(ctx, "SELECT token_hash FROM refresh_tokens WHERE user_id = $1", stored.ID).Scan(&tokenHash)
	if err != nil {
		t.Fatalf("lecture du refresh token en base: %v", err)
	}
	if tokenHash == acc.Refresh {
		t.Fatal("le refresh token est stocke en clair")
	}
	if tokenHash != auth.HashToken(acc.Refresh) {
		t.Fatalf("token_hash %q n'est pas le SHA-256 du jeton", tokenHash)
	}
}

func TestAuth_ExpiredTokensRejected(t *testing.T) {
	s := newSuite(t)
	acc := s.newAccount(t, domain.RoleUser)
	id, _ := uuid.Parse(acc.ID)

	t.Run("jeton d'acces expire", func(t *testing.T) {
		pair, err := s.expired.GenerateTokenPair(&domain.User{ID: id, Email: acc.Email, Username: acc.Username, Role: domain.RoleUser})
		if err != nil {
			t.Fatalf("GenerateTokenPair: %v", err)
		}
		s.do(t, http.MethodGet, "/playlists", pair.AccessToken, nil).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")
	})

	t.Run("refresh token expire", func(t *testing.T) {
		old := "refresh-" + uuid.NewString()
		if err := s.tokens.Store(context.Background(), id, auth.HashToken(old), time.Now().Add(-time.Minute)); err != nil {
			t.Fatalf("Store: %v", err)
		}
		s.do(t, http.MethodPost, "/auth/refresh", "", map[string]any{"refresh_token": old}).
			expect(t, http.StatusUnauthorized, "UNAUTHORIZED")
	})

	t.Run("refresh token inconnu", func(t *testing.T) {
		s.do(t, http.MethodPost, "/auth/refresh", "", map[string]any{"refresh_token": "n-importe-quoi"}).
			expect(t, http.StatusUnauthorized, "UNAUTHORIZED")
	})
}
