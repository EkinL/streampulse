package integration_test

import (
	"context"
	"encoding/base64"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
)

// Injection SQL : toutes les requetes passent par des parametres pgx
// (ADR 005). Une charge utile SQL est stockee comme une chaine, jamais
// executee, et les tables survivent.
func TestSecurity_SQLInjectionIsNeutralised(t *testing.T) {
	s := newSuite(t)
	evilEmail := "bobby-" + uuid.NewString()[:8] + "'); DROP TABLE users; --@evil.test"
	evilName := "Robert'); DROP TABLE streams;--"

	d := s.do(t, http.MethodPost, "/auth/register", "", map[string]any{
		"email": evilEmail, "username": evilName, "password": password, "accepted_terms": true,
	}).expect(t, http.StatusCreated, "").data(t)
	user, _ := d["user"].(map[string]any)
	if str(user, "username") != evilName {
		t.Fatalf("la charge utile doit etre stockee telle quelle: %v", user)
	}

	stored, err := s.users.FindByEmail(context.Background(), evilEmail)
	if err != nil || stored.Username != evilName {
		t.Fatalf("relecture du compte: %+v, %v", stored, err)
	}
	// Les tables visees existent toujours.
	s.do(t, http.MethodGet, "/streams", "", nil).expect(t, http.StatusOK, "")
	s.newAccount(t, domain.RoleUser)
	s.do(t, http.MethodGet, "/streams", "", nil).expect(t, http.StatusOK, "")

	s.do(t, http.MethodPost, "/auth/login", "", map[string]any{"email": "' OR 1=1--", "password": "x"}).
		expect(t, http.StatusUnauthorized, "UNAUTHORIZED")

	// Les charges utiles evitent les chiffres : la recherche plein texte
	// matcherait legitimement le token "1" d'un titre comme "Prise 1".
	for _, q := range []string{"zzqx' OR 'a'='a", "'; DROP TABLE music;--", "\" OR \"\"=\""} {
		escaped := url.QueryEscape(q)
		global := s.do(t, http.MethodGet, "/search?q="+escaped, "", nil).expect(t, http.StatusOK, "").data(t)
		if music, _ := global["music"].([]any); len(music) != 0 {
			t.Fatalf("la recherche %q ne doit rien renvoyer: %v", q, global)
		}
		s.do(t, http.MethodGet, "/music/search?q="+escaped, "", nil).expect(t, http.StatusOK, "")
	}
	s.do(t, http.MethodGet, "/streams/"+url.PathEscape("1 OR 1=1"), "", nil).expect(t, http.StatusBadRequest, "BAD_REQUEST")
}

// tamperRole reecrit le role dans le payload d'un JWT sans le re-signer.
func tamperRole(t *testing.T, token string, from, to domain.Role) string {
	t.Helper()
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("jeton attendu en 3 parties")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatalf("decode payload: %v", err)
	}
	forged := strings.Replace(string(payload), `"role":"`+string(from)+`"`, `"role":"`+string(to)+`"`, 1)
	if forged == string(payload) {
		t.Fatalf("le payload ne contient pas le role %s", from)
	}
	parts[1] = base64.RawURLEncoding.EncodeToString([]byte(forged))
	return strings.Join(parts, ".")
}

// Elevation de privilege par jeton forge : payload modifie, autre secret,
// alg=none. Chaque tentative doit etre un 401 (jeton invalide), jamais un
// 403 (jeton accepte mais role insuffisant), et encore moins un 200.
func TestSecurity_ForgedTokensAreRejected(t *testing.T) {
	s := newSuite(t)
	u := s.newAccount(t, domain.RoleUser)
	id, _ := uuid.Parse(u.ID)
	asAdmin := &domain.User{ID: id, Email: u.Email, Username: u.Username, Role: domain.RoleAdmin}

	forged := tamperRole(t, u.Access, domain.RoleUser, domain.RoleAdmin)
	s.do(t, http.MethodGet, "/admin/users", forged, nil).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")

	otherSecret, err := auth.NewJWTManager("not-the-server-secret", time.Minute, time.Hour).GenerateTokenPair(asAdmin)
	if err != nil {
		t.Fatalf("GenerateTokenPair: %v", err)
	}
	s.do(t, http.MethodGet, "/admin/users", otherSecret.AccessToken, nil).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")

	none, err := jwt.NewWithClaims(jwt.SigningMethodNone, &auth.Claims{
		RegisteredClaims: jwt.RegisteredClaims{Subject: u.ID, ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour))},
		UserID:           u.ID, Role: domain.RoleAdmin,
	}).SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("forge alg=none: %v", err)
	}
	s.do(t, http.MethodGet, "/admin/users", none, nil).expect(t, http.StatusUnauthorized, "UNAUTHORIZED")

	// Pour contraste : le jeton legitime est accepte, et c'est le role qui
	// bloque.
	s.do(t, http.MethodGet, "/admin/users", u.Access, nil).expect(t, http.StatusForbidden, "FORBIDDEN")

	// Un jeton emis pour un autre compte n'ouvre pas les ressources de U.
	v := s.newAccount(t, domain.RoleUser)
	pl := str(s.do(t, http.MethodPost, "/playlists", u.Access, map[string]any{"name": "De U"}).expect(t, http.StatusCreated, "").data(t), "id")
	s.do(t, http.MethodDelete, "/playlists/"+pl, v.Access, nil).expect(t, http.StatusForbidden, "FORBIDDEN")
}

// Mass assignment : aucun champ hors contrat n'est accepte, sur aucune
// ressource. Un client ne peut pas glisser owner_id, role ou id dans un corps.
func TestSecurity_UnknownFieldsRejected(t *testing.T) {
	s := newSuite(t)
	admin := s.newAccount(t, domain.RoleAdmin)
	bc := s.newAccount(t, domain.RoleBroadcaster)
	u := s.newAccount(t, domain.RoleUser)
	pl := str(s.do(t, http.MethodPost, "/playlists", u.Access, map[string]any{"name": "P"}).expect(t, http.StatusCreated, "").data(t), "id")

	cases := []struct {
		method, path, token string
		body                map[string]any
		code                string
	}{
		{http.MethodPost, "/playlists", u.Access, map[string]any{"name": "x", "owner_id": admin.ID}, "BAD_REQUEST"},
		{http.MethodPut, "/playlists/" + pl, u.Access, map[string]any{"name": "x", "owner_id": admin.ID}, "BAD_REQUEST"},
		{http.MethodPost, "/playlists/" + pl + "/tracks", u.Access, map[string]any{"title": "x", "url": "u", "position": 0}, "BAD_REQUEST"},
		{http.MethodPost, "/streams", bc.Access, map[string]any{"title": "x", "status": "live"}, "BAD_REQUEST"},
		{http.MethodPost, "/music", bc.Access, map[string]any{"title": "x", "url": "u", "id": uuid.NewString()}, "INVALID_BODY"},
		{http.MethodPut, "/admin/users/" + u.ID + "/role", admin.Access, map[string]any{"role": "admin", "email": "x"}, "BAD_REQUEST"},
		{http.MethodPost, "/auth/login", "", map[string]any{"email": u.Email, "password": password, "remember": true}, "BAD_REQUEST"},
	}
	for _, tc := range cases {
		t.Run(tc.method+" "+tc.path, func(t *testing.T) {
			s.do(t, tc.method, tc.path, tc.token, tc.body).expect(t, http.StatusBadRequest, tc.code)
		})
	}
}

// Chaque reponse, succes ou erreur, porte un identifiant de correlation :
// c'est ce qui permet de retrouver un incident signale par un utilisateur
// dans les logs (ADR 004).
func TestSecurity_EveryResponseIsCorrelated(t *testing.T) {
	s := newSuite(t)
	u := s.newAccount(t, domain.RoleUser)

	cases := []struct {
		method, path, token string
		status              int
	}{
		{http.MethodGet, "/health", "", http.StatusOK},
		{http.MethodGet, "/streams/" + uuid.NewString(), "", http.StatusNotFound},
		{http.MethodGet, "/playlists", "", http.StatusUnauthorized},
		{http.MethodGet, "/admin/users", u.Access, http.StatusForbidden},
	}
	for _, tc := range cases {
		t.Run(tc.path, func(t *testing.T) {
			r := s.do(t, tc.method, tc.path, tc.token, nil)
			if r.Status != tc.status {
				t.Fatalf("status %d, attendu %d", r.Status, tc.status)
			}
			header := r.Header.Get("X-Request-ID")
			if header == "" {
				t.Fatal("X-Request-ID absent")
			}
			// Les erreurs des middlewares n'ont pas d'enveloppe meta.
			if env := r.envelope(t); env["meta"] != nil {
				if got := str(env["meta"].(map[string]any), "requestId"); got != header {
					t.Fatalf("meta.requestId %q != X-Request-ID %q", got, header)
				}
			}
		})
	}
}
