package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/rs/zerolog"
	"go.opentelemetry.io/otel"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

// logEvent joue une requete a travers la chaine fournie et rend la ligne de log
// decodee.
func logEvent(t *testing.T, wrap func(http.Handler) http.Handler) map[string]any {
	t.Helper()

	var buf strings.Builder
	logger := zerolog.New(&buf)

	handler := Logging(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTeapot)
		_, _ = w.Write([]byte("hello"))
	}))
	if wrap != nil {
		handler = wrap(handler)
	}

	req := httptest.NewRequest(http.MethodGet, "/streams", nil)
	req.Header.Set("User-Agent", "streampulse-test")
	handler.ServeHTTP(httptest.NewRecorder(), req)

	line := strings.TrimSpace(buf.String())
	if line == "" {
		t.Fatal("le middleware n'a rien logue")
	}
	var event map[string]any
	if err := json.Unmarshal([]byte(line), &event); err != nil {
		t.Fatalf("ligne de log illisible: %v\nligne: %s", err, line)
	}
	return event
}

func TestLoggingRecordsRequestFacts(t *testing.T) {
	event := logEvent(t, nil)

	for field, want := range map[string]any{
		"method":     "GET",
		"path":       "/streams",
		"message":    "http request",
		"user_agent": "streampulse-test",
	} {
		if event[field] != want {
			t.Errorf("champ %q = %v, want %v", field, event[field], want)
		}
	}
	// Le status doit etre celui reellement ecrit, pas le 200 par defaut du
	// responseWriter.
	if status, _ := event["status"].(float64); int(status) != http.StatusTeapot {
		t.Errorf("champ \"status\" = %v, want %d", event["status"], http.StatusTeapot)
	}
	if size, _ := event["size"].(float64); int(size) != len("hello") {
		t.Errorf("champ \"size\" = %v, want %d", event["size"], len("hello"))
	}
	if _, ok := event["duration"]; !ok {
		t.Error("champ \"duration\" absent")
	}
}

// TestLoggingIncludesRequestID : sans cet identifiant dans les logs, un
// rapport de bug citant meta.requestId est introuvable.
func TestLoggingIncludesRequestID(t *testing.T) {
	event := logEvent(t, chimiddleware.RequestID)

	reqID, ok := event["request_id"].(string)
	if !ok || reqID == "" {
		t.Fatalf("champ \"request_id\" absent ou vide: %v", event["request_id"])
	}
}

func TestLoggingOmitsRequestIDWhenAbsent(t *testing.T) {
	event := logEvent(t, nil)

	if _, present := event["request_id"]; present {
		t.Errorf("request_id ne doit pas apparaitre sans chimiddleware.RequestID, got %v", event["request_id"])
	}
}

// TestLoggingIncludesTraceID verifie la correlation log <-> trace, et du meme
// coup l'ordre des middlewares : Logging doit etre enregistre APRES le
// middleware qui cree le span, sinon le contexte qu'il observe n'en contient
// aucun.
func TestLoggingIncludesTraceID(t *testing.T) {
	want := trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    trace.TraceID{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10},
		SpanID:     trace.SpanID{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08},
		TraceFlags: trace.FlagsSampled,
	})

	// Un span valide injecte en amont, comme le fait OTELTracing.
	injectSpan := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := trace.ContextWithSpanContext(r.Context(), want)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}

	event := logEvent(t, injectSpan)

	if got := event["trace_id"]; got != want.TraceID().String() {
		t.Errorf("champ \"trace_id\" = %v, want %s", got, want.TraceID())
	}
	if got := event["span_id"]; got != want.SpanID().String() {
		t.Errorf("champ \"span_id\" = %v, want %s", got, want.SpanID())
	}
}

func TestLoggingOmitsTraceIDWhenNoSpan(t *testing.T) {
	event := logEvent(t, nil)

	if _, present := event["trace_id"]; present {
		t.Errorf("trace_id ne doit pas apparaitre sans span, got %v", event["trace_id"])
	}
}

// TestLoggingAfterOTELSeesTheSpan verrouille l'ordre reel des middlewares du
// routeur : OTELTracing d'abord, Logging ensuite. Inverse, le trace_id
// disparait des logs sans qu'aucun test unitaire ne s'en apercoive.
func TestLoggingAfterOTELSeesTheSpan(t *testing.T) {
	// Sans TracerProvider global, otel.Tracer rend un tracer no-op dont le
	// span a un SpanContext invalide : aucun trace_id ne serait emis, et le
	// test passerait pour la mauvaise raison. C'est exactement ce qui se
	// produit en production quand InitTracer echoue au demarrage.
	previous := otel.GetTracerProvider()
	otel.SetTracerProvider(sdktrace.NewTracerProvider(sdktrace.WithSampler(sdktrace.AlwaysSample())))
	t.Cleanup(func() { otel.SetTracerProvider(previous) })

	var buf strings.Builder
	logger := zerolog.New(&buf)
	terminal := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {})

	// Ordre correct : OTELTracing enveloppe Logging.
	OTELTracing("test")(Logging(logger)(terminal)).
		ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/streams", nil))
	correct := buf.String()
	buf.Reset()

	// Ordre inverse : Logging enveloppe OTELTracing, le span lui echappe.
	Logging(logger)(OTELTracing("test")(terminal)).
		ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/streams", nil))
	inverted := buf.String()

	if !strings.Contains(correct, "trace_id") {
		t.Errorf("OTELTracing puis Logging : trace_id devrait etre present, got %s", correct)
	}
	if strings.Contains(inverted, "trace_id") {
		t.Errorf("Logging puis OTELTracing : trace_id ne peut pas etre present, got %s", inverted)
	}
}
