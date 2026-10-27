#!/usr/bin/env bash
# Reset the deployed database to the film-day set, right where you film.
#
#   scripts/film_day.sh <lat> <lng> [HH:MM]
#
# Get lat/lng from Google Maps (long-press your spot). The booking GPS check passes within
# 300 m; live photos pass the time check from 30 minutes before the slot to 3 hours after.
# HH:MM is today's slot in SAST (default: about 10 minutes ago). WIPES the deployed data.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <lat> <lng> [HH:MM]" >&2
  exit 2
fi
cd "$(dirname "$0")/../backend"
if [[ ! -f .env.modal ]]; then
  echo "backend/.env.modal is missing; run scripts/go_live.sh first." >&2
  exit 2
fi
set -a
# shellcheck disable=SC1091
source .env.modal
set +a
read -r -p "This wipes every barber, client and job in the DEPLOYED database. Type yes: " answer
[[ $answer == yes ]] || exit 1
slot=()
[[ $# -ge 3 ]] && slot=(--slot "$3")
MODEL_API_KEY="" STORAGE_BACKEND=supabase uv run python -m fadecall.seed --demo --lat "$1" --lng "$2" ${slot[@]+"${slot[@]}"}
