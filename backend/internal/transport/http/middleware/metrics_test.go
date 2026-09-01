package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/streampulse/backend/internal/infrastructure/observability"
)

// Un seul NewMetrics pour tout le fichier : promauto enregistre dans le
// registre global de Prometheus, un second appel paniquerait (duplicate
// registration).
var testMetrics = observability.NewMetrics()

// TestMetricsCountsRequestsByRoutePattern verifie que le compteur utilise le
// pattern de route ("/streams/{id}") et non l'URL brute ("/streams/42") : un
// label par URL ferait exploser la cardinalite Prometheus.
func TestMetricsCountsRequestsByRoutePattern(t *testing.T) {
	r := chi.NewRouter()
	r.Use(Metrics(testMetrics))
	r.Get("/streams/{id}", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTeapot)
	})

	r.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/streams/42", nil))

	got := testutil.ToFloat64(testMetrics.HTTPRequestsTotal.WithLabelValues("GET", "/streams/{id}", "418"))
	if got != 1 {
		t.Errorf("http_requests_total{GET, /streams/{id}, 418} = %v, want 1", got)
	}
	if series := testutil.CollectAndCount(testMetrics.HTTPRequestDuration); series == 0 {
		t.Error("http_request_duration_seconds n'a enregistre aucune serie")
	}
}

// TestMetricsLabelsUnmatchedRoutes : une URL inconnue ne doit pas creer un
// label par URL scannee (un robot qui balaie /wp-admin, /.env, ... creerait
// une serie par tentative), tout tombe dans "unmatched".
func TestMetricsLabelsUnmatchedRoutes(t *testing.T) {
	r := chi.NewRouter()
	r.Use(Metrics(testMetrics))
	// chi ne monte la chaine de middlewares qu'une fois une route enregistree.
	r.Get("/streams", func(w http.ResponseWriter, r *http.Request) {})

	r.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/wp-admin", nil))
	r.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/.env", nil))

	got := testutil.ToFloat64(testMetrics.HTTPRequestsTotal.WithLabelValues("GET", "unmatched", "404"))
	if got != 2 {
		t.Errorf("http_requests_total{GET, unmatched, 404} = %v, want 2", got)
	}
}
