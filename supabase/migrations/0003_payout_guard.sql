-- At most one live (non-reversed) payout per job: a backstop against a double
-- payout if two proof-of-job pipelines ever race. Reversed rows are history.
create unique index if not exists uq_payouts_active_job
    on payouts (job_id) where status <> 'reversed';
