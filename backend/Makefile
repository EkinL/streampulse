.PHONY: build run test lint migrate docker-build

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

docker-build:
	docker build -t streampulse-api .

clean:
	rm -rf bin/ coverage.out
