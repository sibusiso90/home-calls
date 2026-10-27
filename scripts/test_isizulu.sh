#!/usr/bin/env bash
# Judge Muse Voice Transcribe on a real isiZulu (or any SA language) voice note.
#
#   scripts/test_isizulu.sh path/to/recording.m4a     # any format ffmpeg reads
#
# Converts the recording to mono 16-bit 24 kHz WAV, transcribes it live twice
# (languageBias ["English"] and no bias), and prints both raw transcripts plus
# Muse Spark's cleaned/translated version and the extracted barber profile.
# Needs MODEL_API_KEY (env or backend/.env) and ffmpeg. Makes 4 API calls.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <audio-file>" >&2
  exit 2
fi
if [[ ! -f "$1" ]]; then
  echo "No such file: $1" >&2
  exit 2
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required: brew install ffmpeg" >&2
  exit 2
fi

audio="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")/../backend"
exec uv run python -m fadecall.smoke --voice "$audio"
