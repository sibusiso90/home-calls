#!/usr/bin/env bash
# Pre-submission checks, run from any machine.
#
#   scripts/check_submission.sh --video <public video URL> [--app <deployed app URL>]
#
# 1. The video link opens logged out (no cookies, no login redirect).
# 2. The GitHub repo is public and its README is reachable logged out.
# 3. The deployed app is up and on live models (if --app is given).
# 4. No secrets in tracked files, and no real media committed.
# 5. `make check` passes (skip with --no-check).
set -uo pipefail

video="" app="" run_check=1
while [[ $# -gt 0 ]]; do
  case $1 in
    --video) video=$2; shift 2 ;;
    --app) app=$2; shift 2 ;;
    --no-check) run_check=0; shift ;;
    *) echo "usage: $0 --video <url> [--app <url>] [--no-check]" >&2; exit 2 ;;
  esac
done
cd "$(dirname "$0")/.." || exit 2
fails=0
ok() { printf 'PASS  %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

if [[ -z $video ]]; then
  bad "video: no --video URL given"
else
  # A fresh curl has no cookies, so this is what a logged-out judge sees.
  read -r code final < <(curl -sL -o /dev/null -w '%{http_code} %{url_effective}\n' \
    -A 'Mozilla/5.0 (Macintosh) Safari/605.1.15' "$video")
  if [[ $code != 200 ]]; then
    bad "video: HTTP $code at $final"
  elif [[ $final =~ (login|signin|ServiceLogin|accounts\.google|auth) ]]; then
    bad "video: redirects to a login page ($final); make it public or 'anyone with the link'"
  else
    ok "video opens logged out ($final)"
  fi
fi

remote="$(git remote get-url origin)"
slug="$(sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' <<<"$remote")"
vis="$(curl -s "https://api.github.com/repos/$slug" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("visibility","not found"))')"
if [[ $vis == public ]]; then ok "repo $slug is public"; else bad "repo $slug is $vis (judges must be able to open it)"; fi
if git status --porcelain | grep -q .; then bad "uncommitted changes; commit and push before submitting"; else ok "working tree clean"; fi
if [[ -n "$(git log '@{u}..' 2>/dev/null)" ]]; then bad "local commits not pushed"; else ok "everything pushed"; fi

if [[ -n $app ]]; then
  health="$(curl -fsS "$app/health" 2>/dev/null)"
  if [[ -z $health ]]; then
    bad "app: $app/health unreachable"
  elif grep -q '"mode":"live"' <<<"$health"; then
    ok "app is up on live models"
  else
    bad "app is on mock models: $health"
  fi
fi

leaks="$(git grep -nIE 'sb_secret_[A-Za-z0-9]{10,}|eyJhbGciOi[A-Za-z0-9_-]{20,}|MODEL_API_KEY=[A-Za-z0-9_-]{8,}|sk-[A-Za-z0-9]{20,}' -- . ':!*.lock' | cut -c1-80)"
if [[ -z $leaks ]]; then ok "no secrets in tracked files"; else bad "possible secrets in tracked files:"$'\n'"$leaks"; fi
media="$(git ls-files | grep -iE '\.(jpe?g|png|heic|m4a|mp3|mp4|mov|wav|ogg|aiff?)$' | grep -vE '^(app/web/|app/assets/|backend/samples/|backend/evals/fixtures/)' || true)"
if [[ -z $media ]]; then ok "no real photos, audio or video committed"; else bad "media files committed (check consent):"$'\n'"$media"; fi

if ((run_check)); then
  if make check >/dev/null 2>&1; then ok "make check (lint, tests, web build)"; else bad "make check failed; run it to see why"; fi
fi

echo
((fails == 0)) && echo "Ready to submit." || echo "$fails check(s) failed."
exit $((fails > 0))
