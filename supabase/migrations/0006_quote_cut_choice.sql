-- A quote's cut can come from a reference photo, a catalog pick or our suggestion,
-- and every quote carries face-shape advice. Mirrors backend/src/fadecall/models.py (Quote).

alter table quotes alter column reference_key drop not null;
alter table quotes add column if not exists cut_source  varchar(16) not null default 'reference'
    check (cut_source in ('reference', 'catalog', 'suggested'));
alter table quotes add column if not exists cut_id      varchar(64);
alter table quotes add column if not exists face_advice text;
alter table quotes add column if not exists suggestions jsonb not null default '[]'::jsonb;
