package middleware

import (
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/streampulse/backend/internal/infrastructure/observability"
)

// Metrics alimente http_requests_total et http_request_duration_seconds.
// Le label "path" utilise le pattern de route chi ("/streams/{id}") et non
// l'URL brute : un label par URL ferait exploser la cardinalite Prometheus.
func Metrics(m *observability.Metrics) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()

			rw := &responseWriter{
				ResponseWriter: w,
				status:         http.StatusOK,
			}

			next.ServeHTTP(rw, r)

			// Le pattern n'est connu qu'apres le routage, donc apres ServeHTTP.
			path := chi.RouteContext(r.Context()).RoutePattern()
			if path == "" {
				path = "unmatched"
			}

			m.HTTPRequestsTotal.WithLabelValues(r.Method, path, strconv.Itoa(rw.status)).Inc()
			m.HTTPRequestDuration.WithLabelValues(r.Method, path).Observe(time.Since(start).Seconds())
		})
	}
}
