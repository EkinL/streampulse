package middleware

import (
	"fmt"
	"net/http"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/propagation"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
	"go.opentelemetry.io/otel/trace"
)

func OTELTracing(serviceName string) func(http.Handler) http.Handler {
	tracer := otel.Tracer(serviceName)

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))

			spanName := fmt.Sprintf("%s %s", r.Method, r.URL.Path)
			ctx, span := tracer.Start(ctx, spanName,
				trace.WithAttributes(
					semconv.HTTPMethodKey.String(r.Method),
					semconv.HTTPTargetKey.String(r.URL.Path),
					attribute.String("http.remote_addr", r.RemoteAddr),
				),
				trace.WithSpanKind(trace.SpanKindServer),
			)
			defer span.End()

			rw := &responseWriter{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(rw, r.WithContext(ctx))

			span.SetAttributes(
				semconv.HTTPStatusCodeKey.Int(rw.status),
			)
		})
	}
}
