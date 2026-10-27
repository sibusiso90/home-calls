-- Evidence retention (docs/consent-and-data.md): raw proof-of-job photos are
-- deleted after a final verdict, except for the consented demo set.

alter table jobs add column if not exists consented_demo boolean not null default false;
alter table evidence add column if not exists purged_at timestamptz;

-- Supports the daily purge scan (final verdicts by decision time).
create index if not exists ix_evidence_purge
    on evidence (decided_at) where purged_at is null and verdict in ('pass', 'fail');
