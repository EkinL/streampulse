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
