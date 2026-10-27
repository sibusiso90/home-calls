#!/usr/bin/env bash
# Test the app on a phone (live camera + GPS need a secure context = HTTPS).
#
#   scripts/phone.sh            # cloudflared quick tunnel (public https URL)  [default]
#   scripts/phone.sh lan        # HTTPS on your Wi-Fi with a self-signed cert
#   scripts/phone.sh --dry-run  # validate tools and print the plan; start nothing
#   scripts/phone.sh lan --no-build   # reuse the existing app/build/web
#
# The API and the Flutter web build are served from ONE origin by
# fadecall.webhost (SERVE_WEB_DIR), so the phone only needs one URL and
# there is no CORS or mixed-content trouble. The web app is built with
# API_BASE_URL set to that origin. Ctrl-C stops everything.
#
# Tunnel mode: anyone with the trycloudflare.com URL can reach your local
# server while it runs. Data is the local SQLite DB; demo only.
set -euo pipefail

MODE=tunnel
DRY_RUN=0
BUILD=1
PORT="${PORT:-8000}"
LAN_PORT="${LAN_PORT:-8443}"
for arg in "$@"; do
  case "$arg" in
    tunnel|lan) MODE="$arg" ;;
    --dry-run) DRY_RUN=1 ;;
    --no-build) BUILD=0 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$ROOT/app/build/web"
STATE="$ROOT/backend/.data/phone"
mkdir -p "$STATE"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing $1. $2" >&2; exit 1; }
}

need uv "Install: brew install uv"
if [[ $BUILD -eq 1 ]]; then need flutter "Install Flutter, or pass --no-build"; fi

lan_ip() {
  local ip=""
  if command -v ipconfig >/dev/null 2>&1; then  # macOS
    ip="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then  # Linux
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  echo "$ip"
}

build_web() {  # $1 = API base URL (same origin as the page)
  if [[ $BUILD -eq 0 ]]; then
    [[ -f "$WEB_DIR/index.html" ]] || { echo "No build at $WEB_DIR; drop --no-build" >&2; exit 1; }
    say "Reusing existing web build (API_BASE_URL baked in at its last build!)"
    return
  fi
  say "Building web app with API_BASE_URL=$1"
  (cd "$ROOT/app" && flutter build web --release --dart-define=API_BASE_URL="$1")
}

PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null || true; done; }
trap cleanup EXIT INT TERM

wait_health() {  # $1 = health URL, $2 = extra curl flags
  for _ in $(seq 1 60); do
    # shellcheck disable=SC2086
    curl -sf $2 "$1" >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "API did not come up; see $STATE/api.log" >&2
  exit 1
}

if [[ "$MODE" == "tunnel" ]]; then
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared is not installed. Install it with:" >&2
    echo "    brew install cloudflared" >&2
    echo "or use LAN mode:  scripts/phone.sh lan" >&2
    exit 1
  fi
  if [[ -f "$HOME/.cloudflared/config.yml" || -f "$HOME/.cloudflared/config.yaml" ]]; then
    echo "Note: ~/.cloudflared/config.y(a)ml exists; quick tunnels may refuse to start with it." >&2
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    say "Dry run (tunnel). Would run:"
    echo "  cloudflared tunnel --url http://localhost:$PORT --no-autoupdate"
    echo "  flutter build web --release --dart-define=API_BASE_URL=https://<random>.trycloudflare.com"
    echo "  SERVE_WEB_DIR=$WEB_DIR uv run uvicorn fadecall.webhost:app --port $PORT --proxy-headers --forwarded-allow-ips='*'"
    exit 0
  fi
  say "Starting quick tunnel -> http://localhost:$PORT"
  cloudflared tunnel --url "http://localhost:$PORT" --no-autoupdate >"$STATE/tunnel.log" 2>&1 &
  PIDS+=($!)
  URL=""
  for _ in $(seq 1 60); do
    URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$STATE/tunnel.log" | head -1 || true)"
    [[ -n "$URL" ]] && break
    sleep 1
  done
  [[ -n "$URL" ]] || { echo "No tunnel URL; see $STATE/tunnel.log" >&2; exit 1; }
  build_web "$URL"
  say "Starting API + web on :$PORT"
  # --proxy-headers: trust X-Forwarded-Proto from cloudflared so signed media
  # URLs are https:// (no mixed content on the phone).
  (cd "$ROOT/backend" && SERVE_WEB_DIR="$WEB_DIR" uv run uvicorn fadecall.webhost:app \
    --host 127.0.0.1 --port "$PORT" --proxy-headers --forwarded-allow-ips='*' \
    >"$STATE/api.log" 2>&1) &
  PIDS+=($!)
  wait_health "http://localhost:$PORT/health" ""
else
  need openssl "Install: brew install openssl"
  IP="$(lan_ip)"
  [[ -n "$IP" ]] || { echo "Could not find a LAN IP (are you on Wi-Fi?)" >&2; exit 1; }
  URL="https://$IP:$LAN_PORT"
  KEY="$STATE/lan-$IP.key"
  CRT="$STATE/lan-$IP.crt"
  if [[ ! -f "$CRT" ]]; then
    say "Generating self-signed cert for $IP"
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 -sha256 \
      -keyout "$KEY" -out "$CRT" -subj "/CN=Fade Call dev $IP" \
      -addext "subjectAltName=IP:$IP,DNS:localhost" \
      -addext "extendedKeyUsage=serverAuth" >/dev/null 2>&1
  fi
  openssl x509 -in "$CRT" -noout -ext subjectAltName | grep -q "$IP" \
    || { echo "Cert at $CRT does not cover $IP; delete it and rerun" >&2; exit 1; }
  if [[ $DRY_RUN -eq 1 ]]; then
    say "Dry run (lan). Cert OK: $CRT"
    echo "  flutter build web --release --dart-define=API_BASE_URL=$URL"
    echo "  SERVE_WEB_DIR=$WEB_DIR uv run uvicorn fadecall.webhost:app --host 0.0.0.0 --port $LAN_PORT --ssl-keyfile $KEY --ssl-certfile $CRT"
    exit 0
  fi
  build_web "$URL"
  say "Starting API + web on $URL"
  (cd "$ROOT/backend" && SERVE_WEB_DIR="$WEB_DIR" uv run uvicorn fadecall.webhost:app \
    --host 0.0.0.0 --port "$LAN_PORT" --ssl-keyfile "$KEY" --ssl-certfile "$CRT" \
    >"$STATE/api.log" 2>&1) &
  PIDS+=($!)
  wait_health "https://localhost:$LAN_PORT/health" "-k"
  cat <<NOTE

LAN caveats (self-signed cert):
  - Phone and laptop must be on the same Wi-Fi; the firewall must allow port $LAN_PORT.
  - Android Chrome: tap Advanced -> Proceed; the camera then works.
  - iOS Safari: "Show Details -> visit this website" may still block camera/GPS.
    For reliable iOS testing, AirDrop $CRT to the phone, install the profile, then
    enable it under Settings > General > About > Certificate Trust Settings.
    Or use the tunnel mode (brew install cloudflared), which has a real certificate.
NOTE
fi

echo
say "Open on your phone:  $URL"
if command -v qrencode >/dev/null 2>&1; then qrencode -t ansiutf8 "$URL"; fi
echo "Health: $URL/health   Logs: $STATE/   Ctrl-C to stop."
wait
