.PHONY: up down logs build-all test-backend test-backend-integration test-mobile openapi-lint ipa dart-define mobile-devices mobile-run mobile-run-debug

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f

# L'ordre compte : build_ipa.sh commence par `flutter clean`, qui supprime
# build/ et donc l'APK. Le .ipa passe en premier.
build-all:
	cd backend && make build
	cd mobile && ./scripts/build_ipa.sh
	cd mobile && flutter build apk --release

test-backend:
	cd backend && make test

# Tests d'integration backend : exige une base PostgreSQL jetable dans
# DATABASE_URL (voir docs/plan-de-tests.md).
test-backend-integration:
	cd backend && make test-integration

test-mobile:
	cd mobile && flutter test

# Tests mobile avec le seuil de couverture de la CI (COVERAGE_MIN, voir
# mobile/scripts/coverage_check.sh).
.PHONY: test-mobile-cover
test-mobile-cover:
	cd mobile && flutter test --coverage && ./scripts/coverage_check.sh

# AppBundle iOS non signe (livrable). Necessite Xcode : impossible sur Linux.
# Le .ipa atterrit dans mobile/build/ios/ipa/.
ipa:
	cd mobile && ./scripts/build_ipa.sh

openapi-lint:
	cd backend && make openapi-lint

restart:
	docker compose restart api

ps:
	docker compose ps

# --- Mobile sur appareil physique ---------------------------------------
# Un telephone ne peut pas joindre localhost : pour lui, localhost c'est lui.
# On regenere donc dart_define.json avec l'adresse LAN du Mac a chaque
# lancement, parce qu'elle change de reseau en reseau (DHCP).
LAN_IP := $(shell ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)

dart-define:
	@test -n "$(LAN_IP)" || { echo "Adresse LAN introuvable sur en0/en1. Wi-Fi actif ?"; exit 1; }
	@printf '{\n  "API_BASE_URL": "http://%s:8080"\n}\n' "$(LAN_IP)" > mobile/dart_define.json
	@echo "mobile/dart_define.json -> http://$(LAN_IP):8080"

# DEVICE=<id> pour cibler un appareil precis (voir `make mobile-devices`).
# Sans DEVICE, flutter choisit seul, et il prend souvent le simulateur.
DEVICE ?=
TARGET := $(if $(DEVICE),-d $(DEVICE),)

mobile-devices:
	cd mobile && flutter devices

# --release exige un iPhone physique : Flutter ne compile pas en AOT pour le
# simulateur iOS. Sur simulateur, utiliser mobile-run-debug.
mobile-run: dart-define
	cd mobile && flutter run --release $(TARGET) --dart-define-from-file=dart_define.json

mobile-run-debug: dart-define
	cd mobile && flutter run $(TARGET) --dart-define-from-file=dart_define.json
