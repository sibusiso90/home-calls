-- Model latency shown next to AI output and used for the operator KPI
-- "average verdict time". Mirrors backend/src/fadecall/models.py.

alter table portfolio_items add column if not exists elapsed_ms integer;  -- Muse Spark grading
alter table evidence        add column if not exists elapsed_ms integer;  -- after photo -> model verdict
alter table disputes        add column if not exists elapsed_ms integer;  -- transcribe + summarise
