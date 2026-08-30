package handlers

import (
	"net/http"

	"github.com/streampulse/backend/api"
)

// swaggerUIVersion is pinned on purpose: an unpinned CDN tag would let the
// rendering of our documentation change without a commit on our side.
const swaggerUIVersion = "5.17.14"

// docsPage renders the embedded description with Swagger UI.
//
// The renderer is fetched from a CDN, so this page needs internet access.
// That is deliberate: vendoring the ~1.5 MB Swagger UI bundle into the
// repository to render a document that is already served, machine-readable
// and offline, at /openapi.yaml would be a poor trade. Clients and CI consume
// the YAML; this page is for humans.
const docsPage = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>StreamPulse API</title>
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@` + swaggerUIVersion + `/swagger-ui.css">
<style>
  body { margin: 0; background: #fafafa; }
  .topbar { display: none; }
  noscript { display: block; padding: 2rem; font: 1rem/1.5 system-ui, sans-serif; }
</style>
</head>
<body>
<noscript>
  This page needs JavaScript to render the API description.
  The document itself is available at <a href="/openapi.yaml">/openapi.yaml</a>.
</noscript>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist@` + swaggerUIVersion + `/swagger-ui-bundle.js" crossorigin></script>
<script>
  window.onload = function () {
    window.ui = SwaggerUIBundle({
      url: '/openapi.yaml',
      dom_id: '#swagger-ui',
      deepLinking: true,
      docExpansion: 'none',
      defaultModelsExpandDepth: 0,
      persistAuthorization: true,
      presets: [SwaggerUIBundle.presets.apis],
    });
  };
</script>
</body>
</html>
`

// DocsHandler serves the OpenAPI description and its human-facing renderer.
type DocsHandler struct {
	spec []byte
}

func NewDocsHandler() *DocsHandler {
	return &DocsHandler{spec: api.OpenAPISpec}
}

// Spec serves the raw OpenAPI document.
func (h *DocsHandler) Spec(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/yaml; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(h.spec)
}

// UI serves the Swagger UI page pointing at Spec.
func (h *DocsHandler) UI(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(docsPage))
}
