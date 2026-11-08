# Fade Call: rules for agents and people working in this repo

Verified home-call barbers. Flutter web app (`app/`), FastAPI backend (`backend/`),
Postgres migrations (`supabase/`). Product and architecture live in `docs/`; read
`docs/architecture.md` first, then `backend/README.md` and `app/README.md`.

## Commands (what CI runs)

```bash
make check                       # everything below
cd backend && uv sync --locked && uv run ruff check && uv run ruff format --check && uv run pytest -q
cd app && flutter pub get && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test && flutter build web --release
```

Toolchain: Python 3.12 via `uv` (pinned in `backend/.python-version` and `uv.lock`),
Flutter stable as pinned in `.github/workflows/ci.yml`, ffmpeg on PATH for the
audio tests. Dependabot opens weekly grouped PRs; merge them only when CI is green.

## Hard rules

- **Proof of job is the only path to a payout or a rating.** `services/effects.apply_verdict`
  is the one place pass effects happen; the DB trigger in `0001_init.sql` backs it up.
  Never add another path that releases payment or inserts a rating.
- **The model never auto-fails a job.** Anything short of `pass` is `needs_review`.
- **No real faces or voice notes in the repo.** Only synthetic samples under
  `backend/samples/` and `backend/evals/fixtures/`. `scripts/check_submission.sh` enforces it.
- **No secrets in tracked files.** Local keys go in `backend/.env`; deploy keys in
  `backend/.env.modal` (both gitignored). Never edit `backend/.env.example` with a real value.
- **Schema changes are a new numbered file in `supabase/migrations/`** plus the matching
  SQLAlchemy model. Never edit an applied migration. Keep SQLite (dev) and Postgres (prod) working.
- **API changes update `docs/api-contract.md`** and the Dart models in `app/lib/data/models/`
  in the same change.
- Tests must not depend on the machine's time zone. Format expected times with the app's
  own `formatTime`/`formatSlot` helpers, or build fixtures in UTC.
- Prompts live only in `backend/src/fadecall/ai/prompts.py`; a prompt change needs an eval
  case in `backend/evals/fixtures/cases.json`.

## Workflow

- Work on a branch, keep CI green, and write commit messages that say what changed and why.
- Run the relevant `make check` half before you report a change done; paste the final
  test summary line in the PR.
- `scripts/go_live.sh`, `scripts/film_day.sh` and anything that touches the deployed
  database or Modal are run by a person, not by an agent.

## Layout

```
backend/src/fadecall/   main.py (app factory), config.py, routers/, services/, ai/ (model client,
                        mock, prompts), verdict.py, pricing.py, ranking.py, scheduling.py,
                        storage.py (signed media URLs), seed.py, modal_app.py (deploy + crons)
app/lib/                core/ (config, theme, format), data/ (models, API client),
                        state/ (Riverpod), ui/ (auth, barber, client, ops, widgets), router.dart
supabase/migrations/    0001..000N, applied in order; 0001 creates the private bucket
scripts/                dev.sh, phone.sh, go_live.sh, film_day.sh, live_e2e.py, check_submission.sh
```
