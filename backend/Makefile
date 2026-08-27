.PHONY: build run test lint migrate docker-build openapi-lint openapi-bundle

build:
	go build -o bin/server ./cmd/server

run:
	go run ./cmd/server

test:
	go test -race -coverprofile=coverage.out ./...

test-cover: test
	go tool cover -html=coverage.out

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
