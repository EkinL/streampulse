// Package api embeds the OpenAPI description of the service.
//
// The document is compiled into the binary rather than read from disk at
// runtime: a deployed container has no repository checkout next to it, and
// serving the file the build was made from is the only way the published
// description cannot drift from the routes actually registered.
package api

import _ "embed"

// OpenAPISpec is the OpenAPI 3.1 document served on GET /openapi.yaml.
//
//go:embed openapi.yaml
var OpenAPISpec []byte
