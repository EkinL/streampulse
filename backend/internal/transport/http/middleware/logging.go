package middleware

import (
	"net/http"
	"time"

	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/rs/zerolog"
	"go.opentelemetry.io/otel/trace"
)

type responseWriter struct {
	http.ResponseWriter
	status int
	size   int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.status = code
	rw.ResponseWriter.WriteHeader(code)
}

func (rw *responseWriter) Write(b []byte) (int, error) {
	n, err := rw.ResponseWriter.Write(b)
	rw.size += n
	return n, err
}

func (rw *responseWriter) Flush() {
	if f, ok := rw.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// Unwrap returns the original ResponseWriter for middleware compatibility.
func (rw *responseWriter) Unwrap() http.ResponseWriter {
	return rw.ResponseWriter
}

func Logging(logger zerolog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()

			rw := &responseWriter{
				ResponseWriter: w,
				status:         http.StatusOK,
			}

			next.ServeHTTP(rw, r)

			duration := time.Since(start)

			event := logger.Info().
				Str("method", r.Method).
				Str("path", r.URL.Path).
				Int("status", rw.status).
				Int("size", rw.size).
				Dur("duration", duration).
				Str("remote_addr", r.RemoteAddr).
				Str("user_agent", r.UserAgent())

			// request_id est le meme identifiant que celui renvoye au client
			// dans meta.requestId : c'est ce qui rend un rapport de bug
			// retrouvable dans les logs.
			if reqID := chimiddleware.GetReqID(r.Context()); reqID != "" {
				event = event.Str("request_id", reqID)
			}

			// trace_id relie la ligne de log a la trace distribuee. Absent si
			// le tracer n'est pas initialise (OTEL indisponible au demarrage)
			// ou si ce middleware est enregistre avant OTELTracing.
			if sc := trace.SpanContextFromContext(r.Context()); sc.IsValid() {
				event = event.
					Str("trace_id", sc.TraceID().String()).
					Str("span_id", sc.SpanID().String())
			}

			event.Msg("http request")
		})
	}
}
