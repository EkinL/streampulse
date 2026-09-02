// Package integration_test exerce l'API de bout en bout : routeur complet
// (request id, tracing, CORS, rate-limit, JWT, RBAC), services reels,
// repositories PostgreSQL reels, Hub de diffusion reel. Seul le tracing est
// muet (pas d'exporteur) et les fichiers uploades vont dans un dossier
// temporaire.
//
// Chaque scenario suit un cas d'usage du sujet et un role : il s'authentifie
// comme le ferait l'application mobile, puis verifie les codes HTTP et les
// enveloppes de reponse documentes par api/openapi.yaml.
//
// Execution : DATABASE_URL=postgres://... go test ./internal/integration/
// Sans DATABASE_URL, chaque test est ignore.
package integration_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog"
	"golang.org/x/crypto/bcrypt"

	"github.com/streampulse/backend/internal/application"
	"github.com/streampulse/backend/internal/domain"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/internal/infrastructure/chat"
	"github.com/streampulse/backend/internal/infrastructure/filestore"
	"github.com/streampulse/backend/internal/infrastructure/observability"
	"github.com/streampulse/backend/internal/infrastructure/postgres"
	"github.com/streampulse/backend/internal/infrastructure/streaming"
	transport "github.com/streampulse/backend/internal/transport/http"
	"github.com/streampulse/backend/testutil"
)

const (
	uploadsBaseURL = "http://files.test/uploads"
	password       = "correct-horse-battery"
	jwtSecret      = "integration-secret"
)

// fixtureHash est le hash bcrypt de `password` a cout minimal, partage par
// tous les comptes de fixture (voir newAccount).
var fixtureHash = func() string {
	h, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.MinCost)
	if err != nil {
		panic(err)
	}
	return string(h)
}()

var (
	uploadDir string
	suiteOnce sync.Once
	shared    *suite
)

type suite struct {
	srv     *httptest.Server
	client  *http.Client
	pool    *pgxpool.Pool
	users   *postgres.UserRepo
	tokens  *postgres.RefreshTokenRepo
	jwt     *auth.JWTManager
	expired *auth.JWTManager
	hub     *streaming.Hub
}

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "streampulse-it-uploads-*")
	if err != nil {
		fmt.Fprintln(os.Stderr, "dossier d'upload temporaire:", err)
		os.Exit(1)
	}
	uploadDir = dir

	code := m.Run()

	if shared != nil {
		shared.srv.Close()
	}
	_ = os.RemoveAll(dir)
	os.Exit(code)
}

// newSuite construit le serveur une seule fois par binaire de test :
// observability.NewMetrics enregistre ses collecteurs sur le registre
// Prometheus global, un second routeur paniquerait.
func newSuite(t *testing.T) *suite {
	t.Helper()
	if os.Getenv("DATABASE_URL") == "" {
		t.Skip("DATABASE_URL non defini : test d'integration ignore")
	}
	suiteOnce.Do(func() { shared = buildSuite(t) })
	if shared == nil {
		t.Fatal("la suite n'a pas pu etre construite, voir le premier echec")
	}
	return shared
}

func buildSuite(t *testing.T) *suite {
	t.Helper()
	pool := testutil.OpenTestDB(t, "it_api")
	logger := zerolog.Nop()

	userRepo := postgres.NewUserRepo(pool)
	streamRepo := postgres.NewStreamRepo(pool)
	playlistRepo := postgres.NewPlaylistRepo(pool)
	refreshTokenRepo := postgres.NewRefreshTokenRepo(pool)
	favoriteRepo := postgres.NewFavoriteRepo(pool)
	musicRepo := postgres.NewMusicRepo(pool)
	musicFavoriteRepo := postgres.NewMusicFavoriteRepo(pool)
	feedbackRepo := postgres.NewFeedbackRepo(pool)

	jwtManager := auth.NewJWTManager(jwtSecret, 15*time.Minute, time.Hour)
	hub := streaming.NewHub(logger)
	chatHub := chat.NewHub(logger)
	fileStore := filestore.NewFileStore(uploadDir, uploadsBaseURL)

	router := transport.NewRouter(transport.RouterConfig{
		AuthService:       application.NewAuthService(userRepo, refreshTokenRepo, jwtManager, nil),
		StreamService:     application.NewStreamService(streamRepo, hub),
		PlaylistService:   application.NewPlaylistService(playlistRepo),
		UserService:       application.NewUserService(userRepo, streamRepo, musicRepo, hub, fileStore),
		MusicService:      application.NewMusicService(musicRepo, fileStore),
		FeedbackService:   application.NewFeedbackService(feedbackRepo),
		FavoriteRepo:      favoriteRepo,
		MusicFavoriteRepo: musicFavoriteRepo,
		StreamRepo:        streamRepo,
		MusicRepo:         musicRepo,
		JWTManager:        jwtManager,
		Hub:               hub,
		ChatHub:           chatHub,
		Logger:            logger,
		Metrics:           observability.NewMetrics(),
		CORSOrigins:       "*",
		// Le rate limiting est teste isolement (middleware/ratelimit_test.go) :
		// ici il ne doit pas interferer avec les scenarios.
		RateLimitRPS:   10000,
		RateLimitBurst: 10000,
		ServiceName:    "streampulse-integration",
	})

	return &suite{
		srv:     httptest.NewServer(router),
		client:  &http.Client{},
		pool:    pool,
		users:   userRepo,
		tokens:  refreshTokenRepo,
		jwt:     jwtManager,
		expired: auth.NewJWTManager(jwtSecret, -time.Minute, time.Hour),
		hub:     hub,
	}
}

// --- requetes ----------------------------------------------------------------

type response struct {
	Status int
	Header http.Header
	Raw    []byte
}

// do envoie une requete. body : nil (sans corps), []byte (brut, octet-stream),
// string (envoye tel quel en JSON, pour les corps malformes), ou toute valeur
// serialisee en JSON.
func (s *suite) do(t *testing.T, method, path, token string, body any) response {
	t.Helper()

	var reader io.Reader
	contentType := "application/json"
	switch b := body.(type) {
	case nil:
	case []byte:
		reader = bytes.NewReader(b)
		contentType = "application/octet-stream"
	case string:
		reader = bytes.NewBufferString(b)
	default:
		encoded, err := json.Marshal(b)
		if err != nil {
			t.Fatalf("encodage du corps: %v", err)
		}
		reader = bytes.NewReader(encoded)
	}

	req, err := http.NewRequest(method, s.srv.URL+path, reader)
	if err != nil {
		t.Fatalf("construction de la requete: %v", err)
	}
	if reader != nil {
		req.Header.Set("Content-Type", contentType)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := s.client.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("lecture de la reponse: %v", err)
	}
	return response{Status: resp.StatusCode, Header: resp.Header, Raw: raw}
}

func (r response) envelope(t *testing.T) map[string]any {
	t.Helper()
	var env map[string]any
	if err := json.Unmarshal(r.Raw, &env); err != nil {
		t.Fatalf("reponse non JSON (status %d): %s", r.Status, r.Raw)
	}
	return env
}

// data rend le champ data d'une enveloppe de succes, sous forme d'objet.
func (r response) data(t *testing.T) map[string]any {
	t.Helper()
	d, ok := r.envelope(t)["data"].(map[string]any)
	if !ok {
		t.Fatalf("data n'est pas un objet (status %d): %s", r.Status, r.Raw)
	}
	return d
}

// list rend le champ data d'une enveloppe paginee, sous forme de tableau.
func (r response) list(t *testing.T) []any {
	t.Helper()
	d, ok := r.envelope(t)["data"].([]any)
	if !ok {
		t.Fatalf("data n'est pas un tableau (status %d): %s", r.Status, r.Raw)
	}
	return d
}

func (r response) meta(t *testing.T) map[string]any {
	t.Helper()
	m, ok := r.envelope(t)["meta"].(map[string]any)
	if !ok {
		t.Fatalf("meta absent (status %d): %s", r.Status, r.Raw)
	}
	return m
}

// errorCode rend error.code. Les erreurs des middlewares (401/403/429) n'ont
// pas de meta mais partagent la meme forme {"error":{"code":...}}.
func (r response) errorCode(t *testing.T) string {
	t.Helper()
	e, ok := r.envelope(t)["error"].(map[string]any)
	if !ok {
		t.Fatalf("error absent (status %d): %s", r.Status, r.Raw)
	}
	code, _ := e["code"].(string)
	return code
}

// expect verifie le status et, pour une erreur, le code applicatif.
func (r response) expect(t *testing.T, status int, code string) response {
	t.Helper()
	if r.Status != status {
		t.Fatalf("status %d, attendu %d. Corps: %s", r.Status, status, r.Raw)
	}
	if code != "" {
		if got := r.errorCode(t); got != code {
			t.Fatalf("code d'erreur %q, attendu %q. Corps: %s", got, code, r.Raw)
		}
	}
	return r
}

func str(m map[string]any, key string) string {
	v, _ := m[key].(string)
	return v
}

func containsID(items []any, id string) bool {
	for _, it := range items {
		if m, ok := it.(map[string]any); ok && str(m, "id") == id {
			return true
		}
	}
	return false
}

// --- comptes -----------------------------------------------------------------

type account struct {
	ID       string
	Email    string
	Username string
	Access   string
	Refresh  string
}

func uniqueEmail(prefix string) string {
	return prefix + "-" + uuid.NewString()[:8] + "@it.test"
}

// register cree un compte par l'API, comme le ferait l'application. Un role
// superieur a `user` ne peut pas etre obtenu par l'API (cf. cahier de
// recette, prerequis) : on le pose en base puis on se reconnecte, parce que
// les claims sont figees a l'emission du jeton (ADR 006).
func (s *suite) register(t *testing.T, role domain.Role) account {
	t.Helper()
	email := uniqueEmail(string(role))
	username := string(role) + "-" + email[:8]

	r := s.do(t, http.MethodPost, "/auth/register", "", map[string]any{
		"email": email, "username": username, "password": password, "accepted_terms": true,
	}).expect(t, http.StatusCreated, "")
	d := r.data(t)
	user, _ := d["user"].(map[string]any)
	acc := account{
		ID: str(user, "id"), Email: email, Username: username,
		Access: str(d, "access_token"), Refresh: str(d, "refresh_token"),
	}

	if role != domain.RoleUser {
		id, err := uuid.Parse(acc.ID)
		if err != nil {
			t.Fatalf("id utilisateur invalide %q", acc.ID)
		}
		if err := s.users.UpdateRole(context.Background(), id, role); err != nil {
			t.Fatalf("promotion en %s: %v", role, err)
		}
		acc.Access, acc.Refresh = s.login(t, email)
	}
	return acc
}

// newAccount cree un compte de fixture directement en base, avec un hash bcrypt
// a cout minimal, puis se connecte par l'API. Les jetons sont donc ceux que
// le serveur emet reellement, sans payer un bcrypt a cout 12 par compte :
// sous -race, chaque hachage prend plusieurs secondes. L'inscription par
// l'API, avec son hash a cout 12, reste testee par register (auth_test.go).
func (s *suite) newAccount(t *testing.T, role domain.Role) account {
	t.Helper()
	email := uniqueEmail(string(role))
	username := string(role) + "-" + email[:8]

	user := &domain.User{ID: uuid.New(), Email: email, Username: username, PasswordHash: fixtureHash, Role: role}
	if err := s.users.Create(context.Background(), user); err != nil {
		t.Fatalf("creation du compte %s: %v", role, err)
	}
	access, refresh := s.login(t, email)
	return account{ID: user.ID.String(), Email: email, Username: username, Access: access, Refresh: refresh}
}

func (s *suite) login(t *testing.T, email string) (access, refresh string) {
	t.Helper()
	d := s.do(t, http.MethodPost, "/auth/login", "", map[string]any{
		"email": email, "password": password,
	}).expect(t, http.StatusOK, "").data(t)
	return str(d, "access_token"), str(d, "refresh_token")
}

// --- ressources --------------------------------------------------------------

func (s *suite) createStream(t *testing.T, owner account, title string) string {
	t.Helper()
	d := s.do(t, http.MethodPost, "/streams", owner.Access, map[string]any{
		"title": title, "description": "cree par la suite d'integration",
	}).expect(t, http.StatusCreated, "").data(t)
	return str(d, "id")
}

func (s *suite) addMusicByURL(t *testing.T, owner account, title, artist string) string {
	t.Helper()
	d := s.do(t, http.MethodPost, "/music", owner.Access, map[string]any{
		"title": title, "artist": artist, "album": "", "duration": 180,
		"url": "https://cdn.test/" + uuid.NewString()[:8] + ".mp3",
	}).expect(t, http.StatusCreated, "").data(t)
	return str(d, "id")
}

func waitFor(t *testing.T, timeout time.Duration, cond func() bool, msg string) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("delai de %s depasse : %s", timeout, msg)
}
