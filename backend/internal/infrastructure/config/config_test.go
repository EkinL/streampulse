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
