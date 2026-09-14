-- Found while porting add_post_screen.dart: the Firestore version bumped
-- users.postsCount via a raw client update() with no rules-level
-- protection at all (any owner-authenticated write to their own doc could
-- set it to anything). Rather than port that same unprotected pattern
-- forward, profiles.posts_count is trigger-maintained like every other
-- counter in this schema (see initial_schema.sql's bump_* triggers) --
-- consistent with this migration's own stated preference for
-- database-enforced invariants over client-trusted counters.
alter table public.profiles add column if not exists posts_count integer not null default 0;

create or replace function public.bump_profile_posts_count()
returns trigger security definer set search_path = public, pg_temp
language plpgsql as $$
begin
  if TG_OP = 'INSERT' then
    update public.profiles set posts_count = posts_count + 1 where id = new.user_id;
  elsif TG_OP = 'DELETE' then
    update public.profiles set posts_count = posts_count - 1 where id = old.user_id;
  end if;
  return null;
end;
$$;
create trigger posts_bump_profile_count
  after insert or delete on public.posts
  for each row execute function public.bump_profile_posts_count();
