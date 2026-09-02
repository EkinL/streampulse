package middleware

import (
	"strings"

	"github.com/go-chi/cors"
)

func CORS(allowedOrigins string) func(next interface{}) interface{} {
	origins := strings.Split(allowedOrigins, ",")
	for i := range origins {
		origins[i] = strings.TrimSpace(origins[i])
	}

	return nil // We use chi's cors handler directly
}

func CORSHandler(allowedOrigins string) *cors.Cors {
	origins := strings.Split(allowedOrigins, ",")
	wildcard := false
	for i := range origins {
		origins[i] = strings.TrimSpace(origins[i])
		if origins[i] == "*" {
			wildcard = true
		}
	}

	return cors.New(cors.Options{
		AllowedOrigins: origins,
		AllowedMethods: []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders: []string{"Accept", "Authorization", "Content-Type", "X-Request-ID", "traceparent", "tracestate"},
		ExposedHeaders: []string{"Link", "X-Request-ID"},
		// Les navigateurs refusent la paire `Allow-Origin: *` +
		// `Allow-Credentials: true` : avec le joker, l'annoncer ne sert a rien
		// et ressemble a une mauvaise configuration (observation O-3 du plan
		// de tests). On ne l'annonce que pour des origines nommees.
		AllowCredentials: !wildcard,
		MaxAge:           300,
	})
}
