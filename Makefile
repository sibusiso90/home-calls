# Local pipeline. `make check` runs what CI runs.
API_BASE_URL ?= http://localhost:8000

.PHONY: check backend-check app-check backend app seed dev web deploy local-up local-seed local-reset local-logs local-down

check: backend-check app-check

backend-check:
	cd backend && uv sync && uv run ruff check && uv run ruff format --check && uv run pytest -q

app-check:
	cd app && flutter pub get && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test && flutter build web --release

seed:
	cd backend && uv run python -m fadecall.seed --reset

backend:
	cd backend && uv run uvicorn fadecall.main:app --reload --port 8000

app:
	cd app && flutter run -d chrome --dart-define=API_BASE_URL=$(API_BASE_URL)

# Release web build served next to the API: http://localhost:8080
web:
	cd app && flutter build web --release --dart-define=API_BASE_URL=$(API_BASE_URL) && cd build/web && python3 -m http.server 8080

dev:
	./scripts/dev.sh

# Build the web app against the Modal URL and deploy API + web on one origin (docs/deploy.md).
#   make deploy MODAL_URL=https://<workspace>--fade-call-api.modal.run
deploy:
	@test -n "$(MODAL_URL)" || { echo "usage: make deploy MODAL_URL=https://<workspace>--fade-call-api.modal.run"; exit 2; }
	cd app && flutter build web --release --dart-define=API_BASE_URL=$(MODAL_URL)
	cd backend && FADECALL_WEB_DIR=../app/build/web uv run modal deploy modal_app.py

# Local stack in Docker: Supabase (CLI) + the API image serving the web build. docs/local-docker.md
SUPABASE ?= npx -y supabase@2.120.0
LOCAL_KEY = LOCAL_SUPABASE_SECRET_KEY=$$($(SUPABASE) status -o env | sed -n 's/^SECRET_KEY="\(.*\)"$$/\1/p')

local-up:
	$(SUPABASE) start
	cd app && flutter build web --release --dart-define=API_BASE_URL=http://localhost:8000
	$(LOCAL_KEY) docker compose up -d --build --wait
	@echo "App: http://localhost:8000   Studio: http://localhost:54323"

local-seed:
	$(LOCAL_KEY) docker compose exec api python -m fadecall.seed --reset

# Drops every table and media object, then reapplies supabase/migrations.
local-reset:
	$(SUPABASE) db reset

local-logs:
	$(LOCAL_KEY) docker compose logs -f api

local-down:
	$(LOCAL_KEY) docker compose down
	$(SUPABASE) stop
