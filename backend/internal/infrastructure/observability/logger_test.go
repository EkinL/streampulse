package observability

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/rs/zerolog"
)

func TestIsValidLogFormat(t *testing.T) {
	for _, tt := range []struct {
		format string
		want   bool
	}{
		{LogFormatJSON, true},
		{LogFormatConsole, true},
		{"", false},
		{"JSON", false},
		{"jsonn", false},
		{"text", false},
	} {
		if got := IsValidLogFormat(tt.format); got != tt.want {
			t.Errorf("IsValidLogFormat(%q) = %v, want %v", tt.format, got, tt.want)
		}
	}
}

// TestNewLoggerJSONIsParsable est le test qui porte le critere : un log dit
// "structure pour indexation" doit reellement se parser comme du JSON.
func TestNewLoggerJSONIsParsable(t *testing.T) {
	var buf strings.Builder
	logger := NewLogger("info", LogFormatJSON, "streampulse-test").Output(&buf)

	logger.Info().Str("path", "/streams").Int("status", 200).Msg("http request")

	line := strings.TrimSpace(buf.String())
	var event map[string]any
	if err := json.Unmarshal([]byte(line), &event); err != nil {
		t.Fatalf("la sortie JSON ne se parse pas: %v\nligne: %s", err, line)
	}

	for field, want := range map[string]any{
		"service": "streampulse-test",
		"level":   "info",
		"message": "http request",
		"path":    "/streams",
	} {
		if got, ok := event[field]; !ok {
			t.Errorf("champ %q absent de la ligne de log", field)
		} else if got != want {
			t.Errorf("champ %q = %v, want %v", field, got, want)
		}
	}
	if _, ok := event["time"]; !ok {
		t.Error("champ \"time\" absent : une ligne sans horodatage n'est pas indexable")
	}
	if status, ok := event["status"].(float64); !ok || int(status) != 200 {
		t.Errorf("champ \"status\" = %v, want 200", event["status"])
	}
}

// TestNewLoggerConsoleIsNotJSON verifie que les deux formats different
// reellement : c'est la regression qui a laisse la stack en texte pendant que
// le code pretendait produire du JSON.
func TestNewLoggerConsoleIsNotJSON(t *testing.T) {
	var buf strings.Builder
	logger := NewLogger("info", LogFormatConsole, "streampulse-test").
		Output(zerolog.ConsoleWriter{Out: &buf, NoColor: true})

	logger.Info().Msg("http request")

	line := strings.TrimSpace(buf.String())
	if line == "" {
		t.Fatal("aucune sortie")
	}
	var event map[string]any
	if json.Unmarshal([]byte(line), &event) == nil {
		t.Errorf("le format console produit du JSON, les deux formats sont identiques: %s", line)
	}
	if !strings.Contains(line, "http request") {
		t.Errorf("le message est absent de la sortie console: %s", line)
	}
}

// TestNewLoggerUnknownFormatFallsBackToJSON : un format inconnu ne doit jamais
// produire des logs non indexables en silence.
func TestNewLoggerUnknownFormatFallsBackToJSON(t *testing.T) {
	var buf strings.Builder
	logger := NewLogger("info", "peu-importe", "streampulse-test").Output(&buf)

	logger.Info().Msg("http request")

	var event map[string]any
	if err := json.Unmarshal([]byte(strings.TrimSpace(buf.String())), &event); err != nil {
		t.Fatalf("un format inconnu doit retomber sur JSON, got: %s", buf.String())
	}
}

func TestNewLoggerLevelFiltering(t *testing.T) {
	var buf strings.Builder
	logger := NewLogger("warn", LogFormatJSON, "streampulse-test").Output(&buf)

	logger.Info().Msg("ignore")
	if buf.String() != "" {
		t.Errorf("un evenement info doit etre filtre au niveau warn, got: %s", buf.String())
	}

	logger.Warn().Msg("garde")
	if !strings.Contains(buf.String(), "garde") {
		t.Error("un evenement warn doit passer au niveau warn")
	}
}

// TestNewLoggerInvalidLevelDefaultsToInfo : LOG_LEVEL n'est pas valide au
// demarrage, contrairement a LOG_FORMAT. Le repli doit rester silencieux mais
// previsible.
func TestNewLoggerInvalidLevelDefaultsToInfo(t *testing.T) {
	var buf strings.Builder
	logger := NewLogger("pas-un-niveau", LogFormatJSON, "streampulse-test").Output(&buf)

	logger.Info().Msg("visible")
	if !strings.Contains(buf.String(), "visible") {
		t.Error("un niveau invalide doit retomber sur info")
	}
}

// FormatError est appelee depuis config.Load ; la couverture ne l'attribue pas
// a ce paquet, d'ou ce test direct.
func TestFormatErrorNamesTheValueAndTheAlternatives(t *testing.T) {
	err := FormatError("jsonn")
	if err == nil {
		t.Fatal("FormatError doit rendre une erreur")
	}
	msg := err.Error()
	for _, want := range []string{"jsonn", LogFormatJSON, LogFormatConsole} {
		if !strings.Contains(msg, want) {
			t.Errorf("le message doit citer %q, got: %s", want, msg)
		}
	}
}
