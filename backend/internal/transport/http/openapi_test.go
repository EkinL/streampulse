package http

import (
	"fmt"
	nethttp "net/http"
	"net/http/httptest"
	"regexp"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/rs/zerolog"
	"gopkg.in/yaml.v3"

	"github.com/streampulse/backend/api"
	"github.com/streampulse/backend/internal/infrastructure/auth"
	"github.com/streampulse/backend/internal/infrastructure/observability"
)

// observability.NewMetrics registers its collectors on the global Prometheus
// registry, so building a second router in the same test binary panics on a
// duplicate registration. Every test in this package shares one router.
var (
	testRouterOnce sync.Once
	testRouterMux  *chi.Mux
	testRouterJWT  *auth.JWTManager
)

func testRouter(t *testing.T) (*chi.Mux, *auth.JWTManager) {
	t.Helper()
	testRouterOnce.Do(func() {
		testRouterJWT = auth.NewJWTManager("test-secret", time.Minute, time.Hour)
		testRouterMux = NewRouter(RouterConfig{
			JWTManager:     testRouterJWT,
			Logger:         zerolog.Nop(),
			Metrics:        observability.NewMetrics(),
			CORSOrigins:    "*",
			RateLimitRPS:   1000,
			RateLimitBurst: 1000,
			ServiceName:    "test",
		})
	})
	return testRouterMux, testRouterJWT
}

// openAPIDoc is the subset of the description these tests need: which
// operations exist, and which of them claim to require a bearer token.
type openAPIDoc struct {
	OpenAPI string                          `yaml:"openapi"`
	Info    struct{ Title, Version string } `yaml:"info"`
	// A path item mixes operations with keys such as `parameters`, whose
	// shapes differ, so the values stay raw until the key is known to name
	// an HTTP method.
	Paths map[string]map[string]yaml.Node `yaml:"paths"`
}

type openAPIOperation struct {
	OperationID string                `yaml:"operationId"`
	Security    []map[string][]string `yaml:"security"`
}

var httpMethods = map[string]bool{
	"get": true, "put": true, "post": true, "delete": true,
	"options": true, "head": true, "patch": true, "trace": true,
}

func loadSpec(t *testing.T) openAPIDoc {
	t.Helper()
	var doc openAPIDoc
	if err := yaml.Unmarshal(api.OpenAPISpec, &doc); err != nil {
		t.Fatalf("embedded openapi.yaml is not valid YAML: %v", err)
	}
	if doc.OpenAPI == "" {
		t.Fatal("embedded openapi.yaml has no `openapi` version field")
	}
	if len(doc.Paths) == 0 {
		t.Fatal("embedded openapi.yaml declares no paths")
	}
	return doc
}

// specOperations returns the documented operations as "METHOD /path".
func specOperations(t *testing.T, doc openAPIDoc) map[string]openAPIOperation {
	t.Helper()
	ops := make(map[string]openAPIOperation)
	for path, item := range doc.Paths {
		for method, raw := range item {
			if !httpMethods[strings.ToLower(method)] {
				// `parameters`, `summary`, … live alongside the operations.
				continue
			}
			var op openAPIOperation
			if err := raw.Decode(&op); err != nil {
				t.Fatalf("%s %s: %v", strings.ToUpper(method), path, err)
			}
			ops[strings.ToUpper(method)+" "+path] = op
		}
	}
	return ops
}

// catchAllRoutes are registered with r.Handle, which binds every HTTP method.
// Only the one method that is meaningful is documented.
var catchAllRoutes = map[string]string{
	"/metrics":            "GET",
	"/uploads/{filepath}": "GET",
}

// normalizeRoute maps a chi pattern onto the path key used in the spec.
func normalizeRoute(route string) string {
	// chi reports a sub-router's index route as "/playlists/".
	if len(route) > 1 && strings.HasSuffix(route, "/") {
		route = strings.TrimSuffix(route, "/")
	}
	// chi's wildcard has no OpenAPI equivalent; name the captured segment.
	if strings.HasSuffix(route, "/*") {
		route = strings.TrimSuffix(route, "/*") + "/{filepath}"
	}
	return route
}

// routerOperations walks the real router and returns "METHOD /path" for every
// registered route, normalized onto the spec's vocabulary.
func routerOperations(t *testing.T, r *chi.Mux) map[string]bool {
	t.Helper()
	ops := make(map[string]bool)
	err := chi.Walk(r, func(method, route string, _ nethttp.Handler, _ ...func(nethttp.Handler) nethttp.Handler) error {
		path := normalizeRoute(route)
		if only, isCatchAll := catchAllRoutes[path]; isCatchAll && method != only {
			return nil
		}
		ops[method+" "+path] = true
		return nil
	})
	if err != nil {
		t.Fatalf("walk router: %v", err)
	}
	return ops
}

// TestOpenAPICoversEveryRoute is the guard that keeps the description honest:
// it fails both when a route is added without being documented and when the
// description keeps an operation the router no longer serves.
func TestOpenAPICoversEveryRoute(t *testing.T) {
	router, _ := testRouter(t)
	documented := specOperations(t, loadSpec(t))
	registered := routerOperations(t, router)

	var undocumented []string
	for op := range registered {
		if _, ok := documented[op]; !ok {
			undocumented = append(undocumented, op)
		}
	}
	sort.Strings(undocumented)
	if len(undocumented) > 0 {
		t.Errorf("routes served but missing from api/openapi.yaml:\n  %s",
			strings.Join(undocumented, "\n  "))
	}

	var phantom []string
	for op := range documented {
		if !registered[op] {
			phantom = append(phantom, op)
		}
	}
	sort.Strings(phantom)
	if len(phantom) > 0 {
		t.Errorf("operations documented in api/openapi.yaml but not served by the router:\n  %s",
			strings.Join(phantom, "\n  "))
	}
}

// TestOpenAPIOperationIDsAreUnique catches copy-paste in the description:
// duplicate operationIds silently break every client generator.
func TestOpenAPIOperationIDsAreUnique(t *testing.T) {
	seen := make(map[string]string)
	for op, def := range specOperations(t, loadSpec(t)) {
		if def.OperationID == "" {
			t.Errorf("%s has no operationId", op)
			continue
		}
		if first, dup := seen[def.OperationID]; dup {
			t.Errorf("operationId %q is used by both %s and %s", def.OperationID, first, op)
			continue
		}
		seen[def.OperationID] = op
	}
}

var pathParam = regexp.MustCompile(`\{[^/}]+\}`)

// TestDocumentedAuthMatchesMiddleware checks the description against runtime
// behaviour rather than against itself: every operation that claims to need a
// bearer token must actually be rejected with 401 when called without one.
// These requests never reach a handler, so the nil services above are safe.
func TestDocumentedAuthMatchesMiddleware(t *testing.T) {
	router, _ := testRouter(t)

	for op, def := range specOperations(t, loadSpec(t)) {
		requiresBearer := false
		for _, scheme := range def.Security {
			if _, ok := scheme["bearerAuth"]; ok {
				requiresBearer = true
			}
		}
		if !requiresBearer {
			continue
		}

		method, path, found := strings.Cut(op, " ")
		if !found {
			t.Fatalf("malformed operation key %q", op)
		}
		// A concrete, well-formed value for every path parameter, so that a
		// 400 from id parsing cannot be mistaken for the 401 we expect.
		concrete := pathParam.ReplaceAllString(path, "00000000-0000-4000-8000-000000000000")

		t.Run(fmt.Sprintf("%s %s", method, path), func(t *testing.T) {
			req := httptest.NewRequest(method, concrete, nil)
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, req)

			if rec.Code != nethttp.StatusUnauthorized {
				t.Errorf("documented as requiring bearerAuth, but returned %d without a token (want 401)", rec.Code)
			}
		})
	}
}

// TestDescriptionRoutesArePublic pins the two documentation routes end to end
// through the real middleware chain: a client that cannot read the contract
// before authenticating cannot implement authentication.
func TestDescriptionRoutesArePublic(t *testing.T) {
	router, _ := testRouter(t)

	for _, tc := range []struct {
		path        string
		contentType string
		mustContain string
	}{
		{"/openapi.yaml", "application/yaml", "openapi: 3.1"},
		{"/docs", "text/html", "/openapi.yaml"},
	} {
		t.Run(tc.path, func(t *testing.T) {
			rec := httptest.NewRecorder()
			router.ServeHTTP(rec, httptest.NewRequest(nethttp.MethodGet, tc.path, nil))

			if rec.Code != nethttp.StatusOK {
				t.Fatalf("got status %d without a token, want 200", rec.Code)
			}
			if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, tc.contentType) {
				t.Errorf("got Content-Type %q, want %s", ct, tc.contentType)
			}
			if !strings.Contains(rec.Body.String(), tc.mustContain) {
				t.Errorf("response body does not contain %q", tc.mustContain)
			}
		})
	}
}
