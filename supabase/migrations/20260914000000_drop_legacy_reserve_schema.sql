-- This Supabase project ("ReServe dev") was handed over for the TrueKinn
-- migration already containing an unrelated app's tables (food_posts,
-- users) from its prior use. Confirmed disposable by the project owner
-- before this migration was written — see docs/supabase-migration-plan.md
-- for the record of that decision. Dropping them here, in their own
-- migration, so the drop is an explicit, isolated, auditable step rather
-- than silently folded into the schema-creation migration.
drop table if exists public.food_posts cascade;
drop table if exists public.users cascade;
