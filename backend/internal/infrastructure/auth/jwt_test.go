package auth

import (
	"encoding/base64"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"github.com/streampulse/backend/internal/domain"
)

func testUser(role domain.Role) *domain.User {
	return &domain.User{
		ID:       uuid.New(),
		Email:    string(role) + "@test.local",
		Username: string(role),
		Role:     role,
	}
}

func TestGenerateAndValidateTokenPair(t *testing.T) {
	m := NewJWTManager("unit-secret", 15*time.Minute, 168*time.Hour)
	user := testUser(domain.RoleBroadcaster)

	pair, err := m.GenerateTokenPair(user)
	if err != nil {
		t.Fatalf("GenerateTokenPair: %v", err)
	}
	if pair.AccessToken == "" || pair.RefreshToken == "" {
		t.Fatal("les deux jetons doivent etre emis")
	}
	if _, err := uuid.Parse(pair.RefreshToken); err != nil {
		t.Fatalf("le refresh token doit etre un UUID opaque, obtenu %q", pair.RefreshToken)
	}
	if until := time.Until(pair.ExpiresAt); until < 14*time.Minute || until > 15*time.Minute {
		t.Fatalf("expiration attendue dans ~15 min, obtenu %s", until)
	}

	claims, err := m.ValidateToken(pair.AccessToken)
	if err != nil {
		t.Fatalf("ValidateToken: %v", err)
	}
	if claims.UserID != user.ID.String() || claims.Subject != user.ID.String() {
		t.Errorf("user_id/sub = %s/%s, attendu %s", claims.UserID, claims.Subject, user.ID)
	}
	if claims.Email != user.Email || claims.Username != user.Username || claims.Role != user.Role {
		t.Errorf("claims %+v ne refletent pas l'utilisateur %+v", claims, user)
	}
	if claims.Issuer != "streampulse" {
		t.Errorf("issuer = %q", claims.Issuer)
	}
	if m.RefreshExpiry() != 168*time.Hour {
		t.Errorf("RefreshExpiry = %s", m.RefreshExpiry())
	}
}

// Un jeton expire doit etre refuse : c'est toute la securite du choix "JWT
// court, non revocable" (ADR 006).
func TestValidateTokenRejectsExpired(t *testing.T) {
	expired := NewJWTManager("unit-secret", -time.Minute, time.Hour)
	pair, err := expired.GenerateTokenPair(testUser(domain.RoleUser))
	if err != nil {
		t.Fatalf("GenerateTokenPair: %v", err)
	}
	if _, err := expired.ValidateToken(pair.AccessToken); err == nil {
		t.Fatal("un jeton expire a ete accepte")
	}
}

func TestValidateTokenRejectsWrongSecret(t *testing.T) {
	issuer := NewJWTManager("secret-A", time.Minute, time.Hour)
	verifier := NewJWTManager("secret-B", time.Minute, time.Hour)
	pair, err := issuer.GenerateTokenPair(testUser(domain.RoleAdmin))
	if err != nil {
		t.Fatalf("GenerateTokenPair: %v", err)
	}
	if _, err := verifier.ValidateToken(pair.AccessToken); err == nil {
		t.Fatal("un jeton signe avec un autre secret a ete accepte")
	}
}

// Attaque classique : presenter un jeton "alg: none" non signe. Le keyfunc
// n'accepte que HMAC, le jeton doit etre rejete.
func TestValidateTokenRejectsAlgNone(t *testing.T) {
	m := NewJWTManager("unit-secret", time.Minute, time.Hour)
	user := testUser(domain.RoleUser)
	claims := &Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   user.ID.String(),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		},
		UserID: user.ID.String(),
		Role:   domain.RoleAdmin,
	}
	unsigned, err := jwt.NewWithClaims(jwt.SigningMethodNone, claims).SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("forge du jeton alg=none: %v", err)
	}
	if _, err := m.ValidateToken(unsigned); err == nil {
		t.Fatal("un jeton alg=none a ete accepte")
	}
}

// Elevation de privilege par modification du payload : le role est reecrit
// en "admin" sans re-signer. La signature ne correspond plus, rejet attendu.
func TestValidateTokenRejectsTamperedPayload(t *testing.T) {
	m := NewJWTManager("unit-secret", time.Minute, time.Hour)
	pair, err := m.GenerateTokenPair(testUser(domain.RoleUser))
	if err != nil {
		t.Fatalf("GenerateTokenPair: %v", err)
	}

	parts := strings.Split(pair.AccessToken, ".")
	if len(parts) != 3 {
		t.Fatalf("jeton attendu en 3 parties, obtenu %d", len(parts))
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatalf("decode payload: %v", err)
	}
	forged := strings.Replace(string(payload), `"role":"user"`, `"role":"admin"`, 1)
	if forged == string(payload) {
		t.Fatal("le payload ne contient pas le role attendu, le test ne prouve rien")
	}
	parts[1] = base64.RawURLEncoding.EncodeToString([]byte(forged))

	if _, err := m.ValidateToken(strings.Join(parts, ".")); err == nil {
		t.Fatal("un jeton au payload modifie a ete accepte")
	}
}

func TestValidateTokenRejectsGarbage(t *testing.T) {
	m := NewJWTManager("unit-secret", time.Minute, time.Hour)
	for _, tok := range []string{"", "abc", "a.b.c", "Bearer x"} {
		if _, err := m.ValidateToken(tok); err == nil {
			t.Errorf("jeton %q accepte", tok)
		}
	}
}

func TestHashToken(t *testing.T) {
	h1, h2 := HashToken("refresh-1"), HashToken("refresh-2")
	if len(h1) != 64 {
		t.Fatalf("un SHA-256 hex fait 64 caracteres, obtenu %d", len(h1))
	}
	if h1 == h2 {
		t.Fatal("deux jetons distincts ne peuvent pas partager le meme hash")
	}
	if HashToken("refresh-1") != h1 {
		t.Fatal("le hash doit etre deterministe : c'est la cle de recherche en base")
	}
	if strings.Contains(h1, "refresh") {
		t.Fatal("le hash ne doit pas contenir le jeton en clair")
	}
}
