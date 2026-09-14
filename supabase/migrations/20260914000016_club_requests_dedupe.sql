-- Found during the hardening pass's database-integrity audit (Phase 3):
-- friend_requests and club_join_requests both already have a partial
-- unique index preventing more than one PENDING row for the same party
-- (friend_requests_pending_pair_idx, club_join_requests_pending_idx in
-- 20260914000001_initial_schema.sql) -- club_requests was the one request
-- table missing the same DB-layer invariant, relying only on the client's
-- own _loading-gated submit button (lib/clubs/create_club_screen.dart),
-- which a direct API call or a buggy/modified client can bypass entirely.
-- This also explains two pre-existing stale/junk "Chess Club" pending
-- requests found live during real-user validation testing.
--
-- One pending club-creation request per user at a time, matching the same
-- reasoning as the two existing indexes: a legitimate user has no reason to
-- have two simultaneous pending requests, and the RLS/RPC layer already
-- lets them see and wait on the one they have.
create unique index if not exists club_requests_pending_owner_idx
  on public.club_requests (owner_uid)
  where status = 'pending';
