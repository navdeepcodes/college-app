-- Found while wiring lib/auth/screens/profile_setup_page.dart to Supabase:
-- the profile-completion screen collects nickname/college(display
-- name)/year/branch, none of which were in the initial profiles schema —
-- that schema was built directly from firestore.rules (which only ever
-- validates college_id, anon_id, email), not from every screen's exact
-- field usage. This is the Flutter-cutover equivalent of "static rules
-- review missed something a real flow needed" this whole project keeps
-- re-learning; caught here by actually reading and porting the screen,
-- not guessed at schema-design time.
alter table public.profiles
  add column if not exists nickname text,
  add column if not exists college text,
  add column if not exists year text,
  add column if not exists branch text;
