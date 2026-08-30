package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

func TestDocsHandlerServesSpec(t *testing.T) {
	rec := httptest.NewRecorder()
	NewDocsHandler().Spec(rec, httptest.NewRequest(http.MethodGet, "/openapi.yaml", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("got status %d, want 200", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/yaml") {
		t.Errorf("got Content-Type %q, want application/yaml", ct)
	}

	// The embedded bytes must parse, and must actually be an OpenAPI 3.1
	// document: an embed of the wrong file would still return 200.
	var doc struct {
		OpenAPI string `yaml:"openapi"`
		Info    struct {
			Title   string `yaml:"title"`
			Version string `yaml:"version"`
		} `yaml:"info"`
		Paths map[string]any `yaml:"paths"`
	}
	if err := yaml.Unmarshal(rec.Body.Bytes(), &doc); err != nil {
		t.Fatalf("served spec is not valid YAML: %v", err)
	}
	if !strings.HasPrefix(doc.OpenAPI, "3.1") {
		t.Errorf("got openapi version %q, want 3.1.x", doc.OpenAPI)
	}
	if doc.Info.Title == "" || doc.Info.Version == "" {
		t.Errorf("info.title/info.version must be set, got %q / %q", doc.Info.Title, doc.Info.Version)
	}
	if len(doc.Paths) == 0 {
		t.Error("served spec declares no paths")
	}
}

func TestDocsHandlerServesUI(t *testing.T) {
	rec := httptest.NewRecorder()
	NewDocsHandler().UI(rec, httptest.NewRequest(http.MethodGet, "/docs", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("got status %d, want 200", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Errorf("got Content-Type %q, want text/html", ct)
	}

	body := rec.Body.String()
	// The page is useless if it does not point at the document we serve.
	if !strings.Contains(body, "/openapi.yaml") {
		t.Error("docs page does not reference /openapi.yaml")
	}
	// An unpinned CDN tag would let our documentation change without a commit.
	if !strings.Contains(body, "swagger-ui-dist@"+swaggerUIVersion) {
		t.Errorf("docs page does not load the pinned swagger-ui-dist@%s", swaggerUIVersion)
	}
}
