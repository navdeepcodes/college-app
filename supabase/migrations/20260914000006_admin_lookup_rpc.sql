-- Found while porting create_club_screen.dart: the old Firestore version
-- addressed the club_request notification at a compile-time constant
-- (lib/core/admin.dart's adminUid). Supabase has no equivalent -- admin
-- status is a profiles.is_admin flag the project owner sets by hand on a
-- real account (see docs/supabase-auth-migration.md), and profiles_select
-- gives no ordinary user a way to discover who holds that flag (its
-- college-scoped clause only incidentally reveals it if the admin happens
-- to share the requester's college).
--
-- Rather than loosen profiles_select generally (which would let anyone
-- enumerate is_admin status on arbitrary rows for no real reason), this
-- is a narrow, purpose-built RPC: it returns ONLY the id column of admin
-- rows, callable by any authenticated user, used solely to address a
-- notification. SECURITY DEFINER so it can see admin rows regardless of
-- the caller's own college.
create or replace function public.admin_ids()
returns setof uuid
language sql
security definer
set search_path = public, pg_temp
as $$
  select id from public.profiles where is_admin = true;
$$;

grant execute on function public.admin_ids() to authenticated;
