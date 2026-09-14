-- Found via the beta-hardening pass's own readiness report: Profile screen's
-- "Clubs" stat always reads zero for a genuine club member. Root cause:
-- lib/profile/profile_screen.dart reads profiles.clubs_count, but unlike
-- posts_count (20260914000005_posts_count.sql) and friends_count
-- (initial_schema.sql's bump_friends_count), no such column was ever added
-- and nothing ever wrote it -- every read silently fell through the `?? 0`
-- fallback. Fixed the same way as those two: a trigger-maintained counter
-- on club_members insert/delete, consistent with this schema's existing
-- preference for database-enforced counters over client-trusted ones.
alter table public.profiles add column if not exists clubs_count integer not null default 0;

create or replace function public.bump_profile_clubs_count()
returns trigger security definer set search_path = public, pg_temp
language plpgsql as $$
begin
  if TG_OP = 'INSERT' then
    update public.profiles set clubs_count = clubs_count + 1 where id = new.user_id;
  elsif TG_OP = 'DELETE' then
    update public.profiles set clubs_count = clubs_count - 1 where id = old.user_id;
  end if;
  return null;
end;
$$;
create trigger club_members_bump_profile_count
  after insert or delete on public.club_members
  for each row execute function public.bump_profile_clubs_count();

-- Backfill: memberships created before this trigger existed (every real
-- club membership so far, including the beta test accounts' own) would
-- otherwise keep reading 0 forever despite the trigger now being correct
-- going forward.
update public.profiles p
set clubs_count = (
  select count(*) from public.club_members m where m.user_id = p.id
)
where p.clubs_count <> (
  select count(*) from public.club_members m where m.user_id = p.id
);
