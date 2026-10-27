-- Notifications (in-app inbox; WhatsApp copies are optional) and the
-- cancel / reschedule / reminder lifecycle on jobs.
-- Mirrors backend/src/fadecall/models.py (Notification, Job).

create table if not exists notifications (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references users(id) on delete cascade,
    job_id      uuid references jobs(id) on delete set null,
    kind        varchar(32)  not null
                check (kind in ('booking_created', 'job_confirmed', 'deposit_paid',
                                'verdict_pass', 'verdict_needs_review', 'verdict_operator',
                                'dispute_opened', 'dispute_resolved', 'job_cancelled',
                                'job_rescheduled', 'reminder')),
    title       varchar(160) not null,
    body        text not null default '',
    created_at  timestamptz not null default now(),
    read_at     timestamptz
);
create index if not exists ix_notifications_user_created
    on notifications (user_id, created_at desc);
create index if not exists ix_notifications_unread
    on notifications (user_id) where read_at is null;

alter table jobs add column if not exists reminder_sent_at timestamptz;
alter table jobs add column if not exists cancelled_at     timestamptz;
alter table jobs add column if not exists cancelled_by     varchar(16)
    check (cancelled_by in ('client', 'barber'));
alter table jobs add column if not exists cancel_reason    text;
alter table jobs add column if not exists rescheduled_at   timestamptz;

-- The hourly reminder scan: live jobs that have not been reminded yet.
create index if not exists ix_jobs_reminder_due
    on jobs (slot_start) where reminder_sent_at is null and status in ('booked', 'confirmed');
