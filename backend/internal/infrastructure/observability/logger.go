package observability

import (
	"fmt"
	"io"
	"os"
	"time"

	"github.com/rs/zerolog"
)

// Formats de sortie acceptes par LOG_FORMAT.
const (
	// LogFormatJSON produit une ligne JSON par evenement. C'est le defaut :
	// c'est le seul format indexable par Loki ou Elasticsearch.
	LogFormatJSON = "json"
	// LogFormatConsole produit du texte colore, lisible par un humain. A
	// reserver au developpement local.
	LogFormatConsole = "console"
)

// ValidLogFormats liste les valeurs acceptees, pour les messages d'erreur.
var ValidLogFormats = []string{LogFormatJSON, LogFormatConsole}

// IsValidLogFormat indique si format est une valeur connue de LOG_FORMAT.
func IsValidLogFormat(format string) bool {
	for _, f := range ValidLogFormats {
		if format == f {
			return true
		}
	}
	return false
}

// NewLogger construit le logger de l'application.
//
// Le format est pilote par LOG_FORMAT, pas par APP_ENV : le format de sortie
// et l'environnement sont deux preoccupations distinctes. Les lier revenait a
// devoir mentir sur l'environnement (APP_ENV=production sur un poste de dev)
// pour obtenir des logs indexables.
//
// format est suppose valide : config.Load le rejette au demarrage. Une valeur
// inconnue retombe malgre tout sur JSON, pour qu'un chemin d'appel oublie ne
// produise jamais des logs non indexables en silence.
func NewLogger(level, format, serviceName string) zerolog.Logger {
	lvl, err := zerolog.ParseLevel(level)
	if err != nil {
		lvl = zerolog.InfoLevel
	}

	var out io.Writer = os.Stdout
	if format == LogFormatConsole {
		out = zerolog.ConsoleWriter{
			Out:        os.Stdout,
			TimeFormat: time.RFC3339,
		}
	}

	return zerolog.New(out).
		Level(lvl).
		With().
		Timestamp().
		Str("service", serviceName).
		Logger()
}

// FormatError decrit une valeur de LOG_FORMAT invalide.
func FormatError(format string) error {
	return fmt.Errorf("format de log %q inconnu, attendu %v", format, ValidLogFormats)
}
