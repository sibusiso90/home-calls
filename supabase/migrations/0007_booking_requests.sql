-- Booking requests: the client asks for a day and time windows; the chosen barber
-- has a few minutes to accept, then every barber in range is asked. The barber who
-- accepts picks the start time, which creates the job.
-- Mirrors backend/src/fadecall/models.py (BookingRequest, Notification).

create table if not exists booking_requests (
    id                uuid primary key default gen_random_uuid(),
    quote_id          uuid not null references quotes(id),
    client_id         uuid not null references clients(id),
    day               varchar(10) not null,
    windows           jsonb not null default '[]'::jsonb,
    address           text not null,
    lat               double precision not null,
    lng               double precision not null,
    chosen_barber_id  uuid references barbers(id),
    offered_until     timestamptz,
    broadcast_at      timestamptz,
    declined_by       jsonb not null default '[]'::jsonb,
    status            varchar(16) not null default 'open'
                      check (status in ('open', 'accepted', 'expired', 'cancelled')),
    job_id            uuid references jobs(id),
    closed_at         timestamptz,
    created_at        timestamptz not null default now()
);
create index if not exists ix_booking_requests_open
    on booking_requests (created_at) where status = 'open';
alter table booking_requests enable row level security;

alter table notifications add column if not exists request_id uuid
    references booking_requests(id) on delete set null;

alter table notifications drop constraint if exists notifications_kind_check;
alter table notifications add constraint notifications_kind_check
    check (kind in ('booking_created', 'job_confirmed', 'deposit_paid',
                    'verdict_pass', 'verdict_needs_review', 'verdict_operator',
                    'dispute_opened', 'dispute_resolved', 'job_cancelled',
                    'job_rescheduled', 'reminder',
                    'request_new', 'request_accepted', 'request_update'));
