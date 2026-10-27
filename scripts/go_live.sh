#!/usr/bin/env bash
# Guided go-live: hosted Supabase + Modal + web app, then the live end-to-end check.
#
#   scripts/go_live.sh
#
# The script does docs/deploy.md for you. You only have to:
#   1. Create a Supabase project at supabase.com and have three values ready:
#      the Session pooler URI (Connect -> Session pooler), the project URL and a
#      secret key (Project Settings -> API Keys, `sb_secret_...`).
#   2. Log in to Modal in the browser when asked (first run only).
# Safe to re-run: it keeps an existing backend/.env.modal, skips migrations that
# have already been applied and only seeds an empty database.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/backend"
envfile=.env.modal

say_step() { printf '\n== %s\n' "$1"; }

say_step "1/6 Secrets file (backend/.env.modal, gitignored)"
if [[ -f $envfile ]]; then
  echo "Using the existing $envfile."
else
  read -r -p "Supabase Session pooler URI (postgresql://postgres.<ref>:...:5432/postgres): " db_url
  read -r -p "Supabase project URL (https://<ref>.supabase.co): " sb_url
  read -r -s -p "Supabase secret key (sb_secret_..., hidden): " sb_key
  echo
  model_key="$(sed -n 's/^MODEL_API_KEY=//p' .env 2>/dev/null || true)"
  passcode="fade-$(openssl rand -hex 12)"
  umask 077
  {
    echo "DATABASE_URL=$db_url"
    echo "SUPABASE_URL=$sb_url"
    echo "SUPABASE_SERVICE_KEY=$sb_key"
    echo "SECRET_KEY=$(openssl rand -hex 32)"
    echo "OPERATOR_PASSCODE=$passcode"
    if [[ -n $model_key ]]; then echo "MODEL_API_KEY=$model_key"; fi
  } >"$envfile"
  echo "Wrote $envfile. Operator passcode: $passcode (also in that file)."
fi

say_step "2/6 Database migrations"
set -a
# shellcheck disable=SC1090
source "$envfile"
set +a
uv run python - <<'EOF'
import glob, os, psycopg
with psycopg.connect(os.environ["DATABASE_URL"], autocommit=True) as c:
    c.execute("create table if not exists _fadecall_migrations (name text primary key)")
    done = {r[0] for r in c.execute("select name from _fadecall_migrations")}
    # A database migrated by hand before this script existed: record what is already there.
    if not done and c.execute("select to_regclass('public.barbers')").fetchone()[0]:
        raise SystemExit("Tables exist but no migration record. Apply the missing files by hand "
                         "(see docs/deploy.md), then insert their names into _fadecall_migrations.")
    for f in sorted(glob.glob("../supabase/migrations/*.sql")):
        name = os.path.basename(f)
        if name in done:
            print("skip ", name)
            continue
        with c.transaction():
            c.execute(open(f).read())
            c.execute("insert into _fadecall_migrations values (%s)", (name,))
        print("apply", name)
EOF

say_step "3/6 Demo seed (only into an empty database)"
barbers="$(uv run python -c "import os, psycopg
with psycopg.connect(os.environ['DATABASE_URL']) as c: print(c.execute('select count(*) from barbers').fetchone()[0])")"
if [[ $barbers == 0 ]]; then
  MODEL_API_KEY="" STORAGE_BACKEND=supabase uv run python -m fadecall.seed
else
  echo "Database already has $barbers barber(s); not seeding."
fi

say_step "4/6 Modal login"
if ! uv run modal token info >/dev/null 2>&1; then
  echo "A browser window opens; sign in to Modal (GitHub login works)."
  uv run modal setup
fi
workspace="$(uv run modal profile current)"
url="https://${workspace}--fade-call-api.modal.run"
if ! grep -q '^PUBLIC_BASE_URL=' "$envfile"; then
  echo "PUBLIC_BASE_URL=$url" >>"$envfile"
fi
uv run modal secret create fadecall --from-dotenv "$envfile" --force

say_step "5/6 Build the web app and deploy API + web to $url"
make -C "$root" deploy MODAL_URL="$url"
curl -fsS "$url/health"
echo

say_step "6/6 Live end-to-end check against $url"
uv run python ../scripts/live_e2e.py --base "$url" --passcode "$OPERATOR_PASSCODE"

cat <<EOF

Live at $url
Operator passcode: $OPERATOR_PASSCODE
Next: open the URL on an Android phone (Chrome) and an iPhone (Safari) and follow
docs/deploy.md section 5. Demo day: FADECALL_MIN_CONTAINERS=1 make deploy MODAL_URL=$url
EOF
