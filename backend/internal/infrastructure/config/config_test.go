package config

import (
	"os"
	"path/filepath"
	"testing"
)

func writeEnvFile(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), ".env")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	return path
}

func TestLoadFromEnvFileSetsUnsetVariables(t *testing.T) {
	const key = "STREAMPULSE_TEST_SET"
	_ = os.Unsetenv(key)
	t.Cleanup(func() { _ = os.Unsetenv(key) })

	LoadFromEnvFile(writeEnvFile(t, key+"=from-file\n"))

	if got := os.Getenv(key); got != "from-file" {
		t.Fatalf("%s = %q, attendu %q", key, got, "from-file")
	}
}

func TestLoadFromEnvFileDoesNotOverrideExisting(t *testing.T) {
	const key = "STREAMPULSE_TEST_KEEP"
	t.Setenv(key, "from-env")

	LoadFromEnvFile(writeEnvFile(t, key+"=from-file\n"))

	if got := os.Getenv(key); got != "from-env" {
		t.Fatalf("l'environnement reel doit primer sur le .env (12-Factor), obtenu %q", got)
	}
}

func TestLoadFromEnvFileKeepsWholeValueAfterFirstEquals(t *testing.T) {
	const key = "STREAMPULSE_TEST_URL"
	_ = os.Unsetenv(key)
	t.Cleanup(func() { _ = os.Unsetenv(key) })

	LoadFromEnvFile(writeEnvFile(t, key+"=postgres://u:p@h/db?sslmode=disable\n"))

	if got := os.Getenv(key); got != "postgres://u:p@h/db?sslmode=disable" {
		t.Fatalf("valeur tronquee au premier '=': %q", got)
	}
}

func TestLoadFromEnvFileIgnoresCommentsBlanksAndEmptyKeys(t *testing.T) {
	const key = "STREAMPULSE_TEST_MIX"
	_ = os.Unsetenv(key)
	t.Cleanup(func() { _ = os.Unsetenv(key) })

	// "=orphan" (cle vide) couvre le garde ajoute avec le fix errcheck :
	// avant lui, os.Setenv("", ...) etait tente et son erreur ignoree.
	LoadFromEnvFile(writeEnvFile(t, "# commentaire\n\n=orphan\n"+key+"=ok\r\n"))

	if got := os.Getenv(key); got != "ok" {
		t.Fatalf("%s = %q, attendu %q (CRLF mal gere ?)", key, got, "ok")
	}
}

func TestLoadFromEnvFileMissingFileIsANoOp(t *testing.T) {
	LoadFromEnvFile(filepath.Join(t.TempDir(), "absent.env"))
}

// setMinimalEnv pose les variables requises pour que Load aboutisse, afin que
// les tests ci-dessous n'echouent que sur ce qu'ils ciblent.
func setMinimalEnv(t *testing.T) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://u:p@localhost:5432/db?sslmode=disable")
	t.Setenv("JWT_SECRET", "test-secret")
}

func TestLoadDefaultsLogFormatToJSON(t *testing.T) {
	setMinimalEnv(t)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	// Le defaut doit etre indexable : c'est la regression corrigee ici, la
	// stack tournait en texte parce que le format suivait APP_ENV.
	if cfg.LogFormat != "json" {
		t.Errorf("LogFormat = %q, attendu %q", cfg.LogFormat, "json")
	}
}

func TestLoadAcceptsConsoleLogFormat(t *testing.T) {
	setMinimalEnv(t)
	t.Setenv("LOG_FORMAT", "console")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.LogFormat != "console" {
		t.Errorf("LogFormat = %q, attendu %q", cfg.LogFormat, "console")
	}
}

// TestLoadRejectsUnknownLogFormat : on echoue au demarrage plutot que de
// retomber en silence sur un defaut. Une faute de frappe donnerait sinon des
// logs non indexables en production sans que personne ne le voie.
func TestLoadRejectsUnknownLogFormat(t *testing.T) {
	setMinimalEnv(t)
	t.Setenv("LOG_FORMAT", "jsonn")

	cfg, err := Load()
	if err == nil {
		t.Fatalf("Load doit echouer sur un format inconnu, obtenu %+v", cfg)
	}
}

// TestLoadLogFormatIsIndependentOfAppEnv verrouille la decision de conception :
// le format de log ne doit plus dependre de l'environnement.
func TestLoadLogFormatIsIndependentOfAppEnv(t *testing.T) {
	setMinimalEnv(t)
	t.Setenv("APP_ENV", "development")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.IsDevelopment() {
		t.Fatal("APP_ENV=development doit rester un environnement de developpement")
	}
	if cfg.LogFormat != "json" {
		t.Errorf("LogFormat = %q en developpement : le format ne doit plus suivre APP_ENV", cfg.LogFormat)
	}
}

func TestLoadTLSDisabledByDefault(t *testing.T) {
	setMinimalEnv(t)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if cfg.TLSEnabled() {
		t.Fatal("TLS ne doit pas etre actif sans TLS_CERT_FILE / TLS_KEY_FILE")
	}
	if cfg.RefreshTokenPurgeInterval <= 0 {
		t.Fatalf("REFRESH_TOKEN_PURGE_INTERVAL doit avoir un defaut positif, obtenu %s", cfg.RefreshTokenPurgeInterval)
	}
}

func TestLoadTLSEnabledWithBothFiles(t *testing.T) {
	setMinimalEnv(t)
	t.Setenv("TLS_CERT_FILE", "/certs/fullchain.pem")
	t.Setenv("TLS_KEY_FILE", "/certs/privkey.pem")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !cfg.TLSEnabled() {
		t.Fatal("TLS doit etre actif quand les deux fichiers sont renseignes")
	}
}

// TestLoadRejectsHalfTLSConfig : un seul des deux fichiers est une erreur de
// deploiement. On refuse de demarrer plutot que de servir en clair en
// croyant servir en HTTPS.
func TestLoadRejectsHalfTLSConfig(t *testing.T) {
	for _, only := range []string{"TLS_CERT_FILE", "TLS_KEY_FILE"} {
		t.Run(only, func(t *testing.T) {
			setMinimalEnv(t)
			t.Setenv(only, "/certs/one.pem")
			if cfg, err := Load(); err == nil {
				t.Fatalf("Load doit echouer avec %s seul, obtenu %+v", only, cfg)
			}
		})
	}
}

func TestLoadRejectsNonPositivePurgeInterval(t *testing.T) {
	setMinimalEnv(t)
	t.Setenv("REFRESH_TOKEN_PURGE_INTERVAL", "0s")
	if cfg, err := Load(); err == nil {
		t.Fatalf("Load doit refuser un intervalle nul, obtenu %+v", cfg)
	}
}

func TestPublicBaseURLFollowsTLSAndPort(t *testing.T) {
	setMinimalEnv(t)
	t.Setenv("PORT", "8443")
	t.Setenv("TLS_CERT_FILE", "/certs/fullchain.pem")
	t.Setenv("TLS_KEY_FILE", "/certs/privkey.pem")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got := cfg.PublicBaseURL(); got != "https://localhost:8443" {
		t.Errorf("PublicBaseURL = %q, attendu https://localhost:8443", got)
	}
}

func TestPublicBaseURLOverride(t *testing.T) {
	setMinimalEnv(t)
	t.Setenv("PUBLIC_BASE_URL", "https://api.example.com/")
	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if got := cfg.PublicBaseURL(); got != "https://api.example.com" {
		t.Errorf("PublicBaseURL = %q, attendu https://api.example.com sans barre finale", got)
	}
}
