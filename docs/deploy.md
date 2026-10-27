# Deploy runbook

Going live: Supabase, then Modal, then the web app, then the live checks. Run the commands from the repo root unless a step says otherwise. Allow about 30 minutes.

Only the Python tooling is needed: `uv run modal` comes from the backend's dev dependencies, so there is no Modal or Supabase CLI to install.

## 1. Supabase: database and private bucket

1. Create a project at supabase.com (region: South Africa if offered, else the nearest EU region). Save the database password.
2. **Connect** → **Session pooler** → copy the URI. It looks like `postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`.
   - Don't use the direct `db.<ref>.supabase.co` host, which is IPv6-only, or the transaction pooler on port 6543, which breaks psycopg prepared statements.
3. **Project Settings → API Keys**: copy the project URL (`https://<ref>.supabase.co`) and a secret key (`sb_secret_…`). The legacy `service_role` JWT also works.
4. Write `backend/.env.modal` (gitignored; never commit it). Get `<workspace>` from `uv run modal profile current` after step 2's `modal setup`.

   ```bash
   DATABASE_URL=postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
   SUPABASE_URL=https://<ref>.supabase.co
   SUPABASE_SERVICE_KEY=sb_secret_...
   SECRET_KEY=<openssl rand -hex 32>
   OPERATOR_PASSCODE=<choose one>
   PUBLIC_BASE_URL=https://<workspace>--fade-call-api.modal.run
   MODEL_API_KEY=<when it arrives; leave the line out until then>
   ```

5. Apply the migrations in order. Run them once, on an empty database.

   ```bash
   cd backend
   set -a; source .env.modal; set +a
   uv run python -c "import glob, os, psycopg
   with psycopg.connect(os.environ['DATABASE_URL'], autocommit=True) as c:
       for f in sorted(glob.glob('../supabase/migrations/*.sql')):
           print(f); c.execute(open(f).read())"
   ```

   If you'd rather use the browser, paste each file into the SQL editor in order.
6. Check: **Storage** lists a bucket `fadecall-private` with Public off. `0001_init.sql` creates it. If it is missing, create it by hand as private.
7. Seed the demo data. It uses mock models and writes its media to the bucket:

   ```bash
   STORAGE_BACKEND=supabase uv run python -m fadecall.seed     # still in backend/, env sourced
   ```

## 2. Modal: token, secret, deploy

```bash
cd backend
uv run modal setup                      # browser login; writes ~/.modal.toml
uv run modal profile current            # your <workspace> name, used in the URL
uv run modal secret create fadecall --from-dotenv .env.modal    # --force to update later
uv run modal deploy modal_app.py
curl https://<workspace>--fade-call-api.modal.run/health
```

- The secret must hold `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `SECRET_KEY` and `OPERATOR_PASSCODE`, or the deploy fails. `MODEL_API_KEY` is optional; without it `/health` reports `"mode": "mock"`.
- The image is Debian slim with Python 3.12, ffmpeg, and the dependencies from `uv.lock` (including `meta-sam-parser`). `fadecall` is mounted from your checkout, and the image sets `ENV=prod` and `STORAGE_BACKEND=supabase`.
- The deploy also schedules two crons (Africa/Johannesburg): `purge_evidence` daily at 02:00 and `send_reminders` hourly at :05. Check them in the Modal dashboard under the `fade-call-api` app.
- `modal serve modal_app.py` gives a temporary `…--fade-call-api-dev.modal.run` URL with hot reload.
- After changing a secret, redeploy so new containers pick it up.

## 3. Web app on the same origin

Build the Flutter app against the Modal URL and deploy again with the build included. One origin means no CORS and no mixed content.

```bash
make deploy MODAL_URL=https://<workspace>--fade-call-api.modal.run
```

This runs `flutter build web --release --dart-define=API_BASE_URL=…` and then `FADECALL_WEB_DIR=../app/build/web modal deploy`. The deploy refuses a build that still points at `localhost:8000`.

- Once the web app is on Modal, always deploy through `make deploy`. A plain `modal deploy` without `FADECALL_WEB_DIR` drops the web app.
- On demo day, keep one container warm to avoid cold starts. This costs money:

  ```bash
  FADECALL_MIN_CONTAINERS=1 make deploy MODAL_URL=...
  ```

## 4. Live model smoke test (once `MODEL_API_KEY` exists)

```bash
export MODEL_API_KEY=...
(cd backend && uv run python -m fadecall.smoke --list-models)  # our 3 model IDs exist for this key
(cd backend && uv run python -m fadecall.smoke)                # Spark, Transcribe, SAM: PASS/FAIL each
scripts/test_isizulu.sh ~/Downloads/note.m4a                   # a real isiZulu voice note (4 calls)
```

Without the key these exit with code 2 and say so. Then put the key in the deployed app and check it from inside the image:

```bash
cd backend
echo "MODEL_API_KEY=$MODEL_API_KEY" >> .env.modal
uv run modal secret create fadecall --from-dotenv .env.modal --force
make -C .. deploy MODAL_URL=https://<workspace>--fade-call-api.modal.run
uv run modal run modal_app.py::smoke    # prints the ffmpeg path, then PASS/FAIL per model
curl https://<workspace>--fade-call-api.modal.run/health   # "mode": "live"
```

In the container the transcription clip is a sine tone, so an empty transcript there is a pass.

Each model call is capped by `MODEL_DEADLINE_S` (60 s, retries included). Past the cap, or on an API error, the app returns 502 `model_error` and doesn't hang. Modal cuts web requests at 150 s.

## 5. Phone test (camera and GPS need HTTPS)

Open `https://<workspace>--fade-call-api.modal.run` on an Android phone in Chrome and an iPhone in Safari. The Modal certificate is real, so there are no warnings.

- [ ] Allow camera and location when prompted; the capture screen shows a live preview, the timestamp and GPS.
- [ ] Barber: record a voice note, then check the transcript, the profile and the read-back.
- [ ] Barber: upload portfolio pairs and check the scores, tier and price band.
- [ ] Client: send a selfie and a reference photo, check the named cut, minutes and price, then ask a barber for a time window today.
- [ ] Barber (second phone): the request shows with a countdown; pick a start time and accept. The client gets "… is coming" and pays the deposit.
- [ ] Job: take the before photo, then the after photo, and check the hair-mask overlays and the verdict. Overlay images must load; if they are broken, check `PUBLIC_BASE_URL`.
- [ ] Operator: log in with `OPERATOR_PASSCODE` and check the review queue.
- [ ] Add to the home screen; the app opens standalone.

If the camera or GPS is blocked: in iOS, check **Settings → Safari → Camera/Location**; in Android, tap the lock icon → **Permissions**.

Fallback with no deploy: `scripts/phone.sh`, a cloudflared tunnel to your laptop (see `backend/README.md`).
