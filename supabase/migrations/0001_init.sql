-- Fade Call initial schema (Postgres / Supabase).
-- Mirrors backend/src/fadecall/models.py. Timestamps are timestamptz (UTC).

create extension if not exists pgcrypto;

create table if not exists users (
    id          uuid primary key default gen_random_uuid(),
    role        varchar(16)  not null check (role in ('barber', 'client', 'operator')),
    name        varchar(120) not null,
    phone       varchar(32),
    phone_key   varchar(160) not null,
    created_at  timestamptz  not null default now(),
    constraint uq_users_role_phone unique (role, phone_key)
);

create table if not exists barbers (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid not null unique references users(id),
    name              varchar(120) not null,
    area_id           varchar(64),
    languages         jsonb not null default '[]'::jsonb,
    years_cutting     integer,
    styles            jsonb not null default '[]'::jsonb,
    availability      text,
    tier              varchar(16) check (tier in ('starter', 'pro', 'elite')),
    price_min_zar     integer,
    price_max_zar     integer,
    grade_average     double precision,
    grade_summary     text,
    verified_jobs     integer not null default 0,
    rating            double precision,
    status            varchar(24) not null default 'onboarding'
                      check (status in ('onboarding', 'pending_approval', 'approved', 'rejected')),
    status_reason     text,
    profile_confirmed boolean not null default false,
    created_at        timestamptz not null default now()
);
create index if not exists ix_barbers_status on barbers (status);

create table if not exists portfolio_items (
    id              uuid primary key default gen_random_uuid(),
    barber_id       uuid not null references barbers(id) on delete cascade,
    before_key      text not null,
    after_key       text not null,
    scores          jsonb not null,
    reasons         jsonb not null,
    overall         double precision not null,
    model_versions  jsonb not null default '{}'::jsonb,
    created_at      timestamptz not null default now()
);
create index if not exists ix_portfolio_barber on portfolio_items (barber_id);

create table if not exists clients (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null unique references users(id),
    name        varchar(120) not null,
    phone       varchar(32),
    area_id     varchar(64),
    created_at  timestamptz not null default now()
);

create table if not exists quotes (
    id                     uuid primary key default gen_random_uuid(),
    client_id              uuid not null references clients(id),
    area_id                varchar(64) not null,
    cut_name               text not null,
    minutes                integer not null,
    fit_issues             jsonb not null default '[]'::jsonb,
    reasons                text not null,
    selfie_key             text not null,
    reference_key          text not null,
    selfie_overlay_key     text,
    reference_overlay_key  text,
    masks                  jsonb not null default '{}'::jsonb,
    elapsed_ms             integer not null default 0,
    model_versions         jsonb not null default '{}'::jsonb,
    created_at             timestamptz not null default now()
);

create table if not exists jobs (
    id              uuid primary key default gen_random_uuid(),
    quote_id        uuid references quotes(id),
    barber_id       uuid not null references barbers(id),
    client_id       uuid not null references clients(id),
    cut             text not null,
    minutes         integer not null,
    quote_zar       integer not null,
    price           jsonb not null default '{}'::jsonb,
    travel_band     varchar(1) not null check (travel_band in ('A', 'B', 'C')),
    slot_start      timestamptz not null,
    slot_end        timestamptz not null,
    address         text not null,
    lat             double precision not null,
    lng             double precision not null,
    status          varchar(24) not null default 'booked'
                    check (status in ('booked', 'confirmed', 'in_progress', 'verifying',
                                      'verified', 'needs_review', 'failed', 'cancelled')),
    payment_status  varchar(24) not null default 'deposit_pending',
    deposit_url     text,
    created_at      timestamptz not null default now()
);
create index if not exists ix_jobs_barber on jobs (barber_id);
create index if not exists ix_jobs_client on jobs (client_id);
create index if not exists ix_jobs_status on jobs (status);
-- One live booking per barber per slot.
create unique index if not exists uq_jobs_barber_slot
    on jobs (barber_id, slot_start) where status <> 'cancelled';

create table if not exists evidence (
    id                  uuid primary key default gen_random_uuid(),
    job_id              uuid not null unique references jobs(id),
    before_key          text,
    after_key           text,
    before_overlay_key  text,
    after_overlay_key   text,
    before_capture      jsonb not null default '{}'::jsonb,
    after_capture       jsonb not null default '{}'::jsonb,
    masks               jsonb not null default '{}'::jsonb,
    checks              jsonb not null default '{}'::jsonb,
    verdict             varchar(16) check (verdict in ('pass', 'needs_review', 'fail')),
    verdict_reasons     jsonb not null default '[]'::jsonb,
    decided_by          varchar(16) check (decided_by in ('model', 'operator')),
    operator_reason     text,
    model_versions      jsonb not null default '{}'::jsonb,
    decided_at          timestamptz,
    created_at          timestamptz not null default now()
);

create table if not exists ratings (
    id          uuid primary key default gen_random_uuid(),
    job_id      uuid not null unique references jobs(id),
    stars       integer not null,
    comment     text,
    created_at  timestamptz not null default now(),
    constraint ck_ratings_stars check (stars between 1 and 5)
);

create table if not exists disputes (
    id                     uuid primary key default gen_random_uuid(),
    job_id                 uuid not null references jobs(id),
    transcript             text not null default '',
    summary                text not null default '',
    client_claim           text not null default '',
    evidence_notes         text not null default '',
    suggested_outcome      varchar(24) check (suggested_outcome in ('release', 'refund', 'partial_refund')),
    outcome                varchar(24) check (outcome in ('release', 'refund', 'partial_refund')),
    resolution_reason      text,
    payment_status_before  varchar(24),
    model_versions         jsonb not null default '{}'::jsonb,
    created_at             timestamptz not null default now(),
    resolved_at            timestamptz
);
create index if not exists ix_disputes_job on disputes (job_id);
-- At most one open dispute per job.
create unique index if not exists uq_disputes_open
    on disputes (job_id) where outcome is null;

create table if not exists payouts (
    id          uuid primary key default gen_random_uuid(),
    job_id      uuid not null references jobs(id),
    barber_id   uuid not null references barbers(id),
    amount_zar  integer not null,
    status      varchar(16) not null default 'released',
    created_at  timestamptz not null default now()
);
create index if not exists ix_payouts_job on payouts (job_id);

-- ---------------------------------------------------------------------------
-- DB-level guard mirroring the app rule: a rating can only be inserted when
-- the job's evidence verdict is 'pass'. The API checks first and returns
-- 409 verdict_required; this trigger is the backstop.
-- ---------------------------------------------------------------------------
create or replace function ratings_require_pass() returns trigger
language plpgsql as $$
begin
    if not exists (
        select 1 from evidence e where e.job_id = new.job_id and e.verdict = 'pass'
    ) then
        raise exception 'verdict_required: rating needs a pass verdict for job %', new.job_id
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists ratings_require_pass on ratings;
create trigger ratings_require_pass
    before insert on ratings
    for each row execute function ratings_require_pass();

-- The backend connects with the service role; keep tables private to the API.
alter table users            enable row level security;
alter table barbers          enable row level security;
alter table portfolio_items  enable row level security;
alter table clients          enable row level security;
alter table quotes           enable row level security;
alter table jobs             enable row level security;
alter table evidence         enable row level security;
alter table ratings          enable row level security;
alter table disputes         enable row level security;
alter table payouts          enable row level security;

-- Private media bucket (served only through the API's signed /media URLs).
-- Guarded so the schema also applies to plain Postgres (no Supabase storage schema).
do $$
begin
    if to_regclass('storage.buckets') is not null then
        insert into storage.buckets (id, name, public)
        values ('fadecall-private', 'fadecall-private', false)
        on conflict (id) do nothing;
    end if;
end;
$$;
