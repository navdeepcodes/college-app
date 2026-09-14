-- lib/moderation/reports_admin_screen.dart uses .stream() on `reports` for
-- the admin queue, mirroring the existing club_requests admin pattern
-- (admin_club_requests_screen.dart) -- .stream() needs its table in the
-- supabase_realtime publication to work at all (this is the exact class of
-- bug 20260914000010 fixed: creating a table and its RLS policies does not
-- imply Realtime publication membership). `blocks` deliberately excluded:
-- nothing in the app streams it, so adding it would violate Phase 4's own
-- "don't enable Realtime on tables that don't need it" principle.
alter publication supabase_realtime add table public.reports;
