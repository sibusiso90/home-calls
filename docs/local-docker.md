# Local stack in Docker

The production setup, run on your own machine: a local Supabase (Postgres and Storage) from the Supabase CLI, and the API in a container built like the Modal image (Python 3.12, ffmpeg, `ENV=prod`, `STORAGE_BACKEND=supabase`), serving the Flutter web build on the same origin. Use it to test against real Postgres and a real private bucket before going live.

Needs Docker Desktop running, Node (for `npx`), Flutter, and about 3 GB of disk.

## Start

```bash
make local-up       # Supabase, then the web build, then the API container
make local-seed     # demo barbers, clients and jobs (mock models)
```

| What | Where |
| --- | --- |
| App and API | http://localhost:8000 (health at `/health`) |
| Supabase Studio: tables, the `fadecall-private` bucket | http://localhost:54323 |
| Postgres | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| Operator passcode | `fadecall-local` |

`supabase start` applies every file in `supabase/migrations/` to the empty database, which also creates the private bucket. `supabase/config.toml` turns off realtime, edge functions, analytics and local email, since the app doesn't use them.

## Live models and WhatsApp

Without a key the API runs on the mock models. To go live, set `MODEL_API_KEY` (and optionally `WHATSAPP_TOKEN` and `WHATSAPP_PHONE_ID`) in `backend/.env`, which is gitignored, then recreate the container. Never put keys in `.env.example`, which is committed.

```bash
make local-up
curl -s localhost:8000/health       # "mode" should now be "live"
docker compose exec api python -m fadecall.smoke
```

## Day to day

```bash
make local-logs     # follow the API logs
make local-reset    # wipe the database and bucket, reapply the migrations
make local-down     # stop the API and Supabase (data is kept)
```

After changing backend code, run `make local-up` again. After changing the app, rebuild it with `cd app && flutter build web --release --dart-define=API_BASE_URL=http://localhost:8000`. The container mounts `app/build/web`, so a browser refresh picks it up.

The API container needs the local Supabase secret key. It isn't stored in `compose.yaml`: the `make local-*` targets read it from `supabase status` and pass it as `LOCAL_SUPABASE_SECRET_KEY`, so start, stop and rebuild the API through `make` rather than calling `docker compose up` directly.
