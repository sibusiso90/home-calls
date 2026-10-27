# Fade Call backend

FastAPI service for Fade Call (verified home-call barbers, Midrand / Centurion).
It implements [`docs/api-contract.md`](../docs/api-contract.md) and calls three Meta
models: Muse Spark, Muse Voice Transcribe and SAM 3.1.

With no `MODEL_API_KEY` set, it runs on **deterministic mock models**
(`/health` → `"mode": "mock"`), so the whole demo works offline.

## Quick start

```bash
cd backend
uv sync                                   # Python 3.12 + deps (uv installs 3.12 if needed)
cp .env.example .env                      # optional
uv run python -m fadecall.seed --reset    # demo data with synthetic images
uv run uvicorn fadecall.main:app --reload --port 8000
```

Open http://localhost:8000/docs for the interactive API. CORS is open, so the
Flutter web app can call it from another port.

Seeded logins (`POST /auth/demo-login`):

| Role | name / phone | Notes |
| --- | --- | --- |
| operator | any name, `passcode` = `OPERATOR_PASSCODE` (default `fadecall-ops`) | |
| client | Lerato, `+27831234567` | one verified+rated job, one needs_review, one disputed |
| barber | Thabo M `+27821234567` (elite), Sipho D `+27822345678` (pro), Kabelo M `+27823456789` (pro), Neo K `+27824567890` (starter) | approved |
| barber | Lwazi N `+27825678901` | pending approval |

Synthetic sample media for manual testing (cartoon heads and a sine-tone WAV; no real
faces) live in `samples/`. Regenerate them with `uv run python -m fadecall.samples`.

```bash
TOKEN=$(curl -s localhost:8000/auth/demo-login -H 'content-type: application/json' \
  -d '{"role":"client","name":"Lerato","phone":"+27831234567"}' | jq -r .token)
curl -s localhost:8000/quotes -H "Authorization: Bearer $TOKEN" \
  -F area_id=midrand-central -F selfie=@samples/selfie.jpg -F reference=@samples/reference.jpg
```

## Environment

All settings are optional; see `.env.example`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `MODEL_API_KEY` | unset → mock | Meta Model API key; set it to go live |
| `MODEL_API_BASE_URL` | `https://api.meta.ai/v1` | |
| `SPARK_MODEL` / `TRANSCRIBE_MODEL` / `SAM_MODEL` | `muse-spark-1.3` / `muse-voice-transcribe-1.0` / `sam-3.1` | |
| `MODEL_TIMEOUT_S`, `MODEL_MAX_RETRIES` | `45`, `3` | Per attempt; retries back off on 429/5xx (honours `Retry-After`) |
| `MODEL_DEADLINE_S` | `60` | Hard cap per model call, retries included; then a clean 502 `model_error` |
| `MOCK_FORCE_REVIEW` | `false` | Mock only: `cut_match` comes back `uncertain` → `needs_review` |
| `MOCK_LATENCY_MS` | `0` | Mock only: simulated model latency |
| `DATABASE_URL` | `sqlite:///./fadecall.db` | Postgres URLs (`postgres://…`) use psycopg 3 |
| `SECRET_KEY` | dev value | Signs bearer tokens and media URLs |
| `OPERATOR_PASSCODE` | `fadecall-ops` | Required for operator demo login |
| `PUBLIC_BASE_URL` | request host | Base of signed `/media/…` URLs |
| `STORAGE_BACKEND` | `local` | `local` (`backend/.data/media`) or `supabase` |
| `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `SUPABASE_BUCKET` | –, –, `fadecall-private` | Private bucket via the Storage REST API |
| `FFMPEG_PATH` | `ffmpeg` | Converts browser audio to mono 16-bit 24 kHz WAV |
| `EVIDENCE_RETENTION_DAYS` | `7` | Raw proof photos are deleted this long after a final verdict |
| `LATE_CANCEL_HOURS` | `2` | A client cancelling closer than this to the slot forfeits a paid deposit |
| `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_ID` | unset | Send WhatsApp copies of notifications (both needed; off by default) |

SQLite tables are created on startup (after a schema change, run `seed --reset`).
For Postgres, apply the migrations in `supabase/migrations/` in order. `0001_init.sql`
includes a trigger that blocks a rating insert unless the job's evidence verdict is `pass`;
`0002_retention.sql` adds `jobs.consented_demo` and `evidence.purged_at`;
`0004_notifications_cancel.sql` adds the `notifications` table and the job cancel,
reschedule and reminder columns.

## Layout

```
src/fadecall/
  main.py          app factory, lifespan, CORS, routers
  config.py        settings (pydantic-settings)
  models.py db.py  SQLAlchemy 2 models; SQLite rating guard trigger
  routers/         system (health/auth/areas/media), barbers, clients, jobs, ops
  services/        onboarding, quotes (match/book), proof, disputes, effects, accounts
  ai/              ModelClient protocol, MetaModelClient (live), MockModelClient,
                   sam.py (SAM wire parsing via meta_sam_parser), prompts.py (all prompts + schemas)
  verdict.py       pure checks + verdict rule
  pricing.py ranking.py scheduling.py areas.py   pure business rules
  imaging.py       photo normalising, hair-change measurement, mask overlays
  storage.py       Local/Supabase storage + HMAC-signed media URLs
  services/retention.py, purge.py   evidence purge
  services/notifications.py, reminders.py   inbox, Notifier (in-app / WhatsApp), reminders
  services/lifecycle.py   cancel, reschedule, free slots
  seed.py samples.py
modal_app.py       Modal deployment
```

Key rules:

- **Verdict:** `pass` only if all 7 checks pass. Anything else, including `upload_fallback`
  capture, gives `needs_review`. The model never auto-fails a job.
- **One place for pass effects:** `services/effects.apply_verdict` (model and operator
  verdicts) releases payment, writes the payout row, increments `verified_jobs` and unlocks
  rating. A dispute holds the payment.
- **hair_changed:** the larger of (a) the relative change in SAM hair-mask area, normalised
  to image area, and (b) the share of pixels inside the before-mask that changed. ≥ 10 % passes,
  5–10 % is uncertain, < 5 % fails.
- **Evidence retention:** `uv run python -m fadecall.purge` (daily `modal.Cron` on Modal)
  deletes raw before/after photos and overlays for final verdicts (`pass`, or operator
  `pass`/`fail`) older than `EVIDENCE_RETENTION_DAYS`. It skips open disputes, `needs_review`
  jobs and jobs flagged with `POST /ops/jobs/{id}/consented-demo` (seeded jobs are flagged).
  Checks, reasons and verdicts stay; the Evidence URLs become null and `purged_at` is set.
- **Notifications and reminders:** every event writes an inbox row (`GET /notifications`).
  `uv run python -m fadecall.reminders` (hourly `modal.Cron`) sends the day-before reminder
  for jobs starting within 24 hours, once per slot (`jobs.reminder_sent_at`; a reschedule
  clears it). `WhatsAppNotifier` is wired but only active when both WhatsApp settings are set.
- **Cancel / reschedule:** before the before-photo only. Paid deposit → `refunded`, or
  `forfeited` when the client cancels under `LATE_CANCEL_HOURS` before the slot. Reschedule
  is client-only, to a free slot (`GET /barbers/{id}/slots`), and needs barber re-confirmation.
- **Language:** Muse Voice Transcribe has no South African language, so transcription is
  biased to `["English"]` with suburb and style keywords. Muse Spark cleans and translates
  the transcript before extracting the profile.

## Tests and lint

```bash
uv run pytest                 # unit + full API flow in mock mode + fake-Meta client tests
uv run ruff check && uv run ruff format --check
```

## Deploy on Modal

Full runbook: [`docs/deploy.md`](../docs/deploy.md). In short:

```bash
cd backend
uv run modal setup                                              # once
uv run modal secret create fadecall --from-dotenv .env.modal    # DATABASE_URL, SUPABASE_*, SECRET_KEY, ...
uv run modal deploy modal_app.py      # https://<workspace>--fade-call-api.modal.run (+ crons)
uv run modal run modal_app.py::smoke  # live model smoke test inside the image
make -C .. deploy MODAL_URL=https://<workspace>--fade-call-api.modal.run   # + web app, one origin
```

The image installs ffmpeg and syncs dependencies from `uv.lock`. On Modal it uses
`STORAGE_BACKEND=supabase`, because container disk is ephemeral.

## Live checks, prompt evals and phone testing

**Live smoke test** (one real call per model; needs `MODEL_API_KEY`, exits 2 without it):

```bash
uv run python -m fadecall.smoke                # Spark (grading prompt + images), Transcribe, SAM "hair"
uv run python -m fadecall.smoke --list-models  # GET /v1/models; checks our three model IDs exist
```

Each line shows PASS/FAIL, the model, latency and an output preview. On macOS the
transcription clip is real speech made with `say`; elsewhere it is a sine tone, which should
give an empty transcript.

**isiZulu voice check.** Record a voice note on your phone, then:

```bash
scripts/test_isizulu.sh ~/Downloads/note.m4a
```

It converts the recording with ffmpeg, transcribes it twice (`languageBias ["English"]` and
no bias), and prints both transcripts with Muse Spark's cleaned/translated text and the profile.

**Prompt evals** run every prompt in `ai/prompts.py` over `evals/fixtures/cases.json`:
transcripts in English, isiZulu/English and Sesotho/English, plus the synthetic sample images.
They check schema validity and simple expectations: valid `area_id`, scores 0–10, different
faces not `pass`, and so on.

```bash
uv run python -m fadecall.evals                 # offline mock (also covered by pytest)
uv run python -m fadecall.evals --live          # real models
uv run python -m fadecall.evals --live --only profile,same_person
```

Reports are written to `evals/reports/<timestamp>.md` (gitignored). Add cases by editing
`cases.json`; images are names from `fadecall.samples.demo_set()`, or files you put in
`evals/fixtures/images/` (synthetic or consented only).

**Phone testing.** The camera and GPS need HTTPS. `scripts/phone.sh` builds the web app and
serves it from the same origin as the API, using `fadecall.webhost` with `SERVE_WEB_DIR`
(opt-in; production is unchanged):

```bash
scripts/phone.sh             # cloudflared quick tunnel, real https URL (brew install cloudflared)
scripts/phone.sh lan         # https://<lan-ip>:8443 with a self-signed cert (openssl)
scripts/phone.sh --dry-run   # check tools and print the plan without starting anything
```

The tunnel URL is public while the script runs, so use it for demos only. The LAN mode prints
iOS caveats: Safari may block the camera behind a self-signed cert unless you install and
trust it.
