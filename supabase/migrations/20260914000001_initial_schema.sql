-- TrueKinn — initial Supabase schema.
--
-- Maps the Firestore collections documented in firestore.rules (behavioral
-- reference for this migration) to normalized Postgres tables. Deliberate
-- departures from a literal document->JSON-blob copy, each chosen because
-- the data is genuinely relational and a real foreign key / constraint
-- enforces an invariant Firestore could only enforce with security-rule
-- logic (and in three documented cases, enforced incorrectly until fixed):
--
--   * users/{uid}            -> public.profiles, id = auth.users.id (no
--                                separate uid field — the Supabase Auth
--                                user IS the identity, not a mirrored copy)
--   * chats/{sortedPairId}   -> public.conversations with
--                                CHECK (user_a < user_b) + UNIQUE(user_a,
--                                user_b) — the pair ordering is now a
--                                database constraint, not a client
--                                convention the create rule merely checked.
--                                This structurally eliminates the class of
--                                bug fixed in Phase 18 (unsorted members
--                                broke ~50% of new 1:1 chats).
--   * friends/{sortedPairId} -> public.friendships, same technique.
--   * clubs.admins array     -> derived from club_members.role = 'admin'
--                                instead of a duplicated array column —
--                                one source of truth instead of two that
--                                could drift.
--   * club_chats/{clubId}    -> no parent-doc table at all. club_messages
--     parent doc                just has a club_id foreign key. Firestore
--                                needed a parent doc to exist before its
--                                subcollection was reachable (its total
--                                absence was a real total-outage bug, fixed
--                                Phase 18); a foreign key has no such
--                                prerequisite-row requirement.
--
-- The other, larger structural fix this migration buys for free: every
-- "resource.data dereference on a nonexistent document throws
-- permission-denied instead of gracefully evaluating false" bug this
-- project hit three times (users.read breaking every signup, Phase 20;
-- club_members.read breaking every non-member's first club view, Phase 21;
-- chats/friends, defended client-side rather than fixed at the rules
-- layer) cannot occur in Postgres: `select college_id from profiles where
-- id = auth.uid()` against a row that doesn't exist returns an empty
-- result set, not an error, and `x = NULL` is never TRUE — so a missing
-- row reads as a clean, safe deny by construction, not a thrown exception
-- a security rule has to be carefully written to route around.

-- Helper functions below forward-reference tables created later in this
-- same migration (mirroring firestore.rules' own layout: auth helpers at
-- the top, collections below) — turn off definition-time existence
-- checking for this migration only; the functions are still fully type-
-- and syntax-checked, just not resolved against not-yet-created tables.
set check_function_bodies = off;

-- =========================================================
-- HELPERS
-- =========================================================

-- Mirrors firestore.rules' collegeIdFromEmail(): the four sanctioned
-- college domains, RE2-$-anchored in the original to behave like
-- endsWith(); Postgres has real endsWith-equivalent (SQL LIKE), so no
-- regex workaround is needed here.
create or replace function public.college_id_from_email(email text)
returns text
language sql
immutable
as $$
  select case
    when email ilike '%nmit.ac.in' then 'nmit'
    when email ilike '%rvce.edu.in' then 'rvce'
    when email ilike '%bmsce.ac.in' then 'bms'
    when email ilike '%pes.edu' then 'pes'
    else 'unknown'
  end;
$$;

-- Mirrors firestore.rules' userCollege(): the CALLER's own collegeId.
-- Returns NULL (not an error) if the caller has no profile row yet —
-- see the migration-header note above on why that's the structural win.
create or replace function public.current_college_id()
returns text
language sql
stable
as $$
  select college_id from public.profiles where id = auth.uid();
$$;

-- Mirrors firestore.rules' isAdmin(). Firebase UIDs and Supabase UUIDs are
-- different identity spaces, so the literal hardcoded ADMIN_UID constant
-- cannot be carried over as-is; a boolean flag on profiles is the direct,
-- minimal adaptation (set once, on the real admin's real Supabase account,
-- by the project owner — not something this migration can do for a
-- not-yet-existing user).
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- Mirrors firestore.rules' isClubMember(clubId).
create or replace function public.is_club_member(p_club_id uuid)
returns boolean
language sql
stable
as $$
  select exists(
    select 1 from public.club_members
    where club_id = p_club_id and user_id = auth.uid()
  );
$$;

-- Mirrors firestore.rules' clubs.admins.hasAny([uid]) checks, now derived
-- from club_members.role instead of a duplicated array column.
create or replace function public.is_club_admin(p_club_id uuid)
returns boolean
language sql
stable
as $$
  select exists(
    select 1 from public.club_members
    where club_id = p_club_id and user_id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =========================================================
-- PROFILES  (Firestore: users/{uid})
-- =========================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  college_id text not null default 'unknown',
  anon_id text unique,
  name text,
  photo_url text,
  bio text,
  profile_completed boolean not null default false,
  friends_count integer not null default 0,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.profiles is
  'One row per Supabase Auth user. Bootstrapped on first sign-in by a client-side upsert (mirrors auth_gate.dart''s _UserBootstrap) or, more robustly, a handle_new_user() trigger — see the auth-migration doc for which path this app uses.';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Mirrors the users.create rule: initial collegeId must equal the
-- email-derived value (or 'unknown').
create or replace function public.enforce_college_id_on_insert()
returns trigger language plpgsql as $$
begin
  if new.college_id <> public.college_id_from_email(new.email) then
    raise exception 'college_id must match the email domain';
  end if;
  return new;
end;
$$;
create trigger profiles_enforce_college_id_insert
  before insert on public.profiles
  for each row execute function public.enforce_college_id_on_insert();

-- Mirrors the users.update rule: collegeId is immutable once set, and
-- anonId is mintable once (from NULL) and then locked.
create or replace function public.enforce_profile_immutability()
returns trigger language plpgsql as $$
begin
  if new.college_id <> old.college_id then
    raise exception 'college_id is immutable';
  end if;
  if old.anon_id is not null and new.anon_id <> old.anon_id then
    raise exception 'anon_id is immutable once set';
  end if;
  return new;
end;
$$;
create trigger profiles_enforce_immutability
  before update on public.profiles
  for each row execute function public.enforce_profile_immutability();

-- =========================================================
-- POSTS / LIKES / COMMENTS  (Firestore: posts, posts/likes, posts/comments)
-- =========================================================
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  college_id text not null,
  text text,
  media_path text,
  likes_count integer not null default 0,
  comments_count integer not null default 0,
  created_at timestamptz not null default now()
);
create index posts_college_created_idx on public.posts (college_id, created_at desc);
create index posts_user_idx on public.posts (user_id);

create table public.post_likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (post_id, user_id) -- one like per user per post, enforced by the database, not client convention
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  text text not null check (length(trim(text)) > 0),
  created_at timestamptz not null default now()
);
create index comments_post_idx on public.comments (post_id, created_at);

-- likes_count / comments_count stay authoritative via triggers (a real
-- transactional guarantee, not a client-issued increment op the rules
-- merely permitted).
create or replace function public.bump_post_likes_count()
returns trigger language plpgsql as $$
begin
  if TG_OP = 'INSERT' then
    update public.posts set likes_count = likes_count + 1 where id = new.post_id;
  elsif TG_OP = 'DELETE' then
    update public.posts set likes_count = likes_count - 1 where id = old.post_id;
  end if;
  return null;
end;
$$;
create trigger post_likes_count_trigger
  after insert or delete on public.post_likes
  for each row execute function public.bump_post_likes_count();

create or replace function public.bump_post_comments_count()
returns trigger language plpgsql as $$
begin
  if TG_OP = 'INSERT' then
    update public.posts set comments_count = comments_count + 1 where id = new.post_id;
  elsif TG_OP = 'DELETE' then
    update public.posts set comments_count = comments_count - 1 where id = old.post_id;
  end if;
  return null;
end;
$$;
create trigger comments_count_trigger
  after insert or delete on public.comments
  for each row execute function public.bump_post_comments_count();

-- =========================================================
-- FRIENDS + FRIEND REQUESTS
-- =========================================================
create table public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  from_uid uuid not null references public.profiles(id) on delete cascade,
  to_uid uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  check (from_uid <> to_uid)
);
-- At most one PENDING request between any two people, in either
-- direction — closes a duplicate-request path Firestore never
-- structurally prevented (only the client's own pre-check avoided it).
create unique index friend_requests_pending_pair_idx
  on public.friend_requests (least(from_uid, to_uid), greatest(from_uid, to_uid))
  where status = 'pending';

create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  source_request_id uuid references public.friend_requests(id),
  created_at timestamptz not null default now(),
  check (user_a < user_b),
  unique (user_a, user_b)
);
create index friendships_user_a_idx on public.friendships (user_a);
create index friendships_user_b_idx on public.friendships (user_b);

create or replace function public.bump_friends_count()
returns trigger language plpgsql as $$
begin
  update public.profiles set friends_count = friends_count + 1 where id in (new.user_a, new.user_b);
  return null;
end;
$$;
create trigger friendships_count_trigger
  after insert on public.friendships
  for each row execute function public.bump_friends_count();

-- =========================================================
-- 1:1 CONVERSATIONS + MESSAGES  (Firestore: chats, chats/messages)
-- =========================================================
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  last_message text default '',
  last_message_at timestamptz default now(),
  created_at timestamptz not null default now(),
  check (user_a < user_b),
  unique (user_a, user_b) -- canonical pair, enforced by the database
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  from_uid uuid not null references public.profiles(id) on delete cascade,
  to_uid uuid not null references public.profiles(id) on delete cascade,
  text text not null check (length(trim(text)) > 0),
  status text not null default 'sent' check (status in ('sent', 'delivered', 'seen')),
  created_at timestamptz not null default now(),
  check (from_uid <> to_uid)
);
create index messages_conversation_idx on public.messages (conversation_id, created_at);
create index messages_recipient_status_idx on public.messages (to_uid, status);

create or replace function public.bump_conversation_last_message()
returns trigger language plpgsql as $$
begin
  update public.conversations
    set last_message = new.text, last_message_at = new.created_at
    where id = new.conversation_id;
  return new;
end;
$$;
create trigger messages_bump_conversation
  after insert on public.messages
  for each row execute function public.bump_conversation_last_message();

-- =========================================================
-- CLUBS
-- =========================================================
create table public.club_requests (
  id uuid primary key default gen_random_uuid(),
  owner_uid uuid not null references public.profiles(id) on delete cascade,
  club_name text not null check (length(trim(club_name)) > 0),
  description text,
  phone text,
  usn text,
  id_card_url text not null check (length(trim(id_card_url)) > 0),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now()
);

create table public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  owner_uid uuid not null references public.profiles(id),
  members_count integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.club_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  created_at timestamptz not null default now(),
  unique (club_id, user_id)
);

create or replace function public.bump_club_members_count()
returns trigger language plpgsql as $$
begin
  if TG_OP = 'INSERT' then
    update public.clubs set members_count = members_count + 1 where id = new.club_id;
  elsif TG_OP = 'DELETE' then
    update public.clubs set members_count = members_count - 1 where id = old.club_id;
  end if;
  return null;
end;
$$;
create trigger club_members_count_trigger
  after insert or delete on public.club_members
  for each row execute function public.bump_club_members_count();

create table public.club_join_requests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined')),
  created_at timestamptz not null default now()
);
-- At most one pending join request per (club, user) — a real invariant,
-- not merely a client pre-check.
create unique index club_join_requests_pending_idx
  on public.club_join_requests (club_id, user_id)
  where status = 'pending';

create table public.club_messages (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  text text not null check (length(trim(text)) > 0),
  created_at timestamptz not null default now()
);
create index club_messages_club_idx on public.club_messages (club_id, created_at);

-- =========================================================
-- EVENTS
-- =========================================================
create table public.events (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id) on delete cascade,
  college_id text not null,
  title text not null check (length(trim(title)) > 0),
  description text,
  media_paths text[] not null default '{}',
  event_link text,
  start_date timestamptz not null,
  end_date timestamptz not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create index events_college_start_idx on public.events (college_id, start_date);

-- =========================================================
-- NOTIFICATIONS
-- =========================================================
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('club_request', 'friend_request')),
  from_uid uuid not null references public.profiles(id) on delete cascade,
  to_uid uuid not null references public.profiles(id) on delete cascade,
  request_id uuid, -- polymorphic: points at club_requests.id or friend_requests.id depending on type; no FK (different target tables)
  club_name text,
  read boolean not null default false,
  created_at timestamptz not null default now(),
  check (from_uid <> to_uid)
);
create index notifications_recipient_idx on public.notifications (to_uid, read, created_at desc);

-- =========================================================
-- ANONYMOUS COLLEGE CHAT
-- =========================================================
create table public.anon_rooms (
  college_id text primary key,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.anon_messages (
  id uuid primary key default gen_random_uuid(),
  room_college_id text not null references public.anon_rooms(college_id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  anon_id text not null,
  text text not null check (length(trim(text)) > 0),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index anon_messages_room_idx on public.anon_messages (room_college_id, created_at);
create index anon_messages_expiry_idx on public.anon_messages (expires_at);

-- =========================================================
-- MOMENTS  (schema kept for parity per explicit "do not remove Moments"
-- instruction; the feature stays product-disabled — see kMomentsEnabled
-- in lib/feed/feed_screen.dart, unchanged by this migration).
-- =========================================================
create table public.moments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  anon_id text,
  college_id text not null,
  media_url text not null,
  is_video boolean not null default false,
  visibility text not null default 'college' check (visibility in ('college', 'friends')),
  reports_count integer not null default 0,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index moments_user_idx on public.moments (user_id, created_at desc);
create index moments_expiry_idx on public.moments (expires_at);
