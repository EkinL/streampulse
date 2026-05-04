.PHONY: up down logs build-all test-backend test-mobile

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f

build-all:
	cd backend && make build
	cd mobile && flutter build apk --release

test-backend:
	cd backend && make test

test-mobile:
	cd mobile && flutter test

restart:
	docker compose restart api

ps:
	docker compose ps
