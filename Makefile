# Local pipeline. `make check` runs what CI runs.
API_BASE_URL ?= http://localhost:8000

.PHONY: check backend-check app-check backend app seed dev web

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
