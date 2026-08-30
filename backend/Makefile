.PHONY: build run test bench load-test lint migrate docker-build openapi-lint openapi-bundle

build:
	go build -o bin/server ./cmd/server

run:
	go run ./cmd/server

# Suite complete. Les tests d'integration tournent si DATABASE_URL est defini,
# sinon ils se declarent ignores. -coverpkg mesure la couverture de tout le
# module, y compris ce que les tests d'integration exercent dans d'autres paquets.
test:
	go test -race -covermode=atomic -coverpkg=./... -coverprofile=coverage.out ./...

test-cover: test
	go tool cover -html=coverage.out

# Preuve de charge du Hub de fan-out (cf. docs/ADR/003-streaming-sse.md).
# bench : cout d'un chunk diffuse a 10 / 100 / 1000 / 10000 auditeurs.
bench:
	go test -run '^$$' -bench 'Hub' -benchmem ./internal/infrastructure/streaming/

# load-test : 1000 auditeurs sur le Hub seul, puis 500 vrais clients SSE
# a travers le routeur complet (JWT, RBAC, rate-limit).
load-test:
	go test -race -count=1 -v -run 'TestHubFanOutNListeners|TestStreamFanOutOverSSE' \
		./internal/infrastructure/streaming/ ./internal/transport/http/

lint:
	golangci-lint run ./...

# La description OpenAPI est la source de verite du contrat REST.
# openapi-lint la valide ; le test Go TestOpenAPICoversEveryRoute verifie
# en plus qu'elle correspond aux routes reellement servies.
openapi-lint:
	npx --yes @redocly/cli@1.25.11 lint api/openapi.yaml

# Document autoportant ($ref resolus), pour les generateurs de clients.
openapi-bundle:
	npx --yes @redocly/cli@1.25.11 bundle api/openapi.yaml -o bin/openapi.bundled.yaml

docker-build:
	docker build -t streampulse-api .

clean:
	rm -rf bin/ coverage.out

.PHONY: test-unit test-integration cover-check

# Suite unitaire seule, sans base : les tests d'integration se declarent
# ignores quand DATABASE_URL est vide.
test-unit:
	DATABASE_URL= go test -race ./...

# Suite d'integration (repositories + API bout en bout) contre une base
# PostgreSQL jetable. Chaque paquet travaille dans son propre schema, la base
# n'a donc besoin ni d'etre vide ni d'etre reinitialisee entre deux runs.
test-integration:
	@test -n "$$DATABASE_URL" || { echo "DATABASE_URL requis, ex. postgres://localhost:5432/streampulse_test?sslmode=disable"; exit 1; }
	go test -race -count=1 ./internal/infrastructure/postgres/ ./internal/integration/

# Seuil de couverture, identique a celui de la CI. Valeur et trajectoire dans
# docs/plan-de-tests.md.
#
# -count=1 est indispensable : un paquet dont le resultat vient du cache ne
# reemet pas sa couverture inter-paquets (-coverpkg), et le total mesure
# s'effondre de plusieurs points sans qu'aucun test n'ait change. La CI part
# d'un runner vierge et n'a pas ce probleme ; en local, sans cette option, le
# seuil se declenche a tort.
COVERAGE_MIN ?= 80
cover-check:
	go test -race -count=1 -coverprofile=coverage.out -covermode=atomic -coverpkg=./... ./...
	@total=$$(go tool cover -func=coverage.out | tail -1 | awk '{print $$3}' | tr -d '%'); \
	echo "couverture totale : $$total % (minimum $(COVERAGE_MIN) %)"; \
	awk -v t="$$total" -v m="$(COVERAGE_MIN)" 'BEGIN { exit (t + 0 < m + 0) ? 1 : 0 }'
