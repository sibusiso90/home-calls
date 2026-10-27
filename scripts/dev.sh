#!/usr/bin/env bash
# Starts the API on :8000 and the Flutter web app in Chrome. Ctrl-C stops both.
set -euo pipefail
cd "$(dirname "$0")/.."

(cd backend && uv run uvicorn fadecall.main:app --reload --port 8000) &
api_pid=$!
trap 'kill $api_pid 2>/dev/null' EXIT

until curl -sf http://localhost:8000/health >/dev/null; do sleep 1; done
echo "API up: $(curl -s http://localhost:8000/health)"

cd app && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
