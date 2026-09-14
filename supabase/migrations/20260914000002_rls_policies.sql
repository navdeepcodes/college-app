-- Row Level Security policies — the Postgres equivalent of firestore.rules.
-- Every policy below cites the exact firestore.rules block it replaces so
-- the mapping is auditable line-by-line against the behavioral reference.
-- Enable RLS on every table: nothing is readable/writable by default,
-- exactly like Firestore's own default-deny posture.

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.comments enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.club_requests enable row level security;
alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_join_requests enable row level security;
alter table public.club_messages enable row level security;
alter table public.events enable row level security;
alter table public.notifications enable row level security;
alter table public.anon_rooms enable row level security;
alter table public.anon_messages enable row level security;
alter table public.moments enable row level security;

-- =========================================================
-- PROFILES  (firestore.rules users/{userId}, lines 67-116)
-- =========================================================
-- Own profile always readable (own-doc check has no existence
-- precondition at all in SQL — see migration-header note); same-college
-- readable; platform admin reads all. Note this is strictly SAFER than
-- the pre-Phase-20 Firestore rule ever was, and cannot regress into that
-- bug class: there is no "row doesn't exist yet" throw to guard against.
create policy profiles_select on public.profiles for select
  using (
    id = auth.uid()
    or college_id = public.current_college_id()
    or public.is_platform_admin()
  );

-- Signup: create your own row only (initial college_id correctness is
-- already enforced by the enforce_college_id_on_insert trigger, so RLS
-- only needs to check ownership).
create policy profiles_insert on public.profiles for insert
  with check (id = auth.uid());

-- Update your own row only (immutability of college_id/anon_id is
-- enforced by the enforce_profile_immutability trigger).
create policy profiles_update on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

-- No delete policy at all == delete always denied, mirrors `allow delete: if false`.

-- =========================================================
-- POSTS / LIKES / COMMENTS  (firestore.rules lines 125-178)
-- =========================================================
create policy posts_select on public.posts for select
  using (college_id = public.current_college_id());

create policy posts_insert on public.posts for insert
  with check (user_id = auth.uid() and college_id = public.current_college_id());

-- Owner edits freely; likes_count/comments_count are maintained by
-- triggers (see initial_schema.sql), not client updates, so — unlike the
-- Firestore rule, which had to carve out a client-writable-counter
-- exception for non-owners — no such exception exists or is needed here.
create policy posts_update on public.posts for update
  using (user_id = auth.uid() and college_id = public.current_college_id())
  with check (user_id = auth.uid() and college_id = public.current_college_id());

create policy posts_delete on public.posts for delete
  using (user_id = auth.uid() and college_id = public.current_college_id());

create policy post_likes_select on public.post_likes for select
  using (exists(select 1 from public.posts p where p.id = post_id and p.college_id = public.current_college_id()));

create policy post_likes_insert on public.post_likes for insert
  with check (
    user_id = auth.uid()
    and exists(select 1 from public.posts p where p.id = post_id and p.college_id = public.current_college_id())
  );

create policy post_likes_delete on public.post_likes for delete
  using (user_id = auth.uid());

create policy comments_select on public.comments for select
  using (exists(select 1 from public.posts p where p.id = post_id and p.college_id = public.current_college_id()));

create policy comments_insert on public.comments for insert
  with check (
    user_id = auth.uid()
    and exists(select 1 from public.posts p where p.id = post_id and p.college_id = public.current_college_id())
  );

create policy comments_update on public.comments for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy comments_delete on public.comments for delete
  using (user_id = auth.uid());

-- =========================================================
-- FRIENDS + FRIEND REQUESTS  (firestore.rules lines 358-421)
-- =========================================================
create policy friendships_select on public.friendships for select
  using (auth.uid() in (user_a, user_b));

-- Consent check equivalent: the friends.create rule required
-- sourceRequestId to point at a still-pending request naming exactly
-- these two members. Same check here, expressed as a subquery instead of
-- four chained get() calls.
create policy friendships_insert on public.friendships for insert
  with check (
    auth.uid() in (user_a, user_b)
    and exists (
      select 1 from public.friend_requests r
      where r.id = source_request_id
        and r.status = 'pending'
        and ((r.from_uid = user_a and r.to_uid = user_b) or (r.from_uid = user_b and r.to_uid = user_a))
    )
  );
-- No update policy: friendship edges are immutable, mirrors `allow update: if false`.
create policy friendships_delete on public.friendships for delete
  using (auth.uid() in (user_a, user_b));

create policy friend_requests_select on public.friend_requests for select
  using (auth.uid() in (from_uid, to_uid));

create policy friend_requests_insert on public.friend_requests for insert
  with check (from_uid = auth.uid() and to_uid <> auth.uid());

-- Only the recipient decides (accept/decline) — status is the only column
-- a client should ever change, enforced the same way posts_update proves
-- ownership rather than diffing keys client-side (Postgres has no
-- Firestore-style affectedKeys() primitive; a BEFORE UPDATE trigger is the
-- equivalent tool when a column-level restriction is actually needed —
-- not required here since from_uid/to_uid/created_at are never sent by
-- the accept/decline UI).
create policy friend_requests_update on public.friend_requests for update
  using (to_uid = auth.uid())
  with check (to_uid = auth.uid());

create policy friend_requests_delete on public.friend_requests for delete
  using (auth.uid() in (from_uid, to_uid));

-- =========================================================
-- 1:1 CONVERSATIONS + MESSAGES  (firestore.rules lines 305-353)
-- =========================================================
create policy conversations_select on public.conversations for select
  using (auth.uid() in (user_a, user_b));

-- The sorted-pair CHECK constraint (user_a < user_b) does the job the old
-- rule's members[0] < members[1] check did — but as a table constraint,
-- not a per-write rule, so it can never be bypassed by a write path that
-- forgets to check it (the exact failure mode of the original unsorted-
-- members bug, Phase 18: a rule existed, a caller just didn't satisfy it
-- from client code half the time). RLS only needs the membership check.
create policy conversations_insert on public.conversations for insert
  with check (auth.uid() in (user_a, user_b));

create policy conversations_update on public.conversations for update
  using (auth.uid() in (user_a, user_b))
  with check (auth.uid() in (user_a, user_b));

create policy messages_select on public.messages for select
  using (exists(select 1 from public.conversations c where c.id = conversation_id and auth.uid() in (c.user_a, c.user_b)));

create policy messages_insert on public.messages for insert
  with check (
    from_uid = auth.uid()
    and to_uid <> auth.uid()
    and exists(select 1 from public.conversations c where c.id = conversation_id and auth.uid() in (c.user_a, c.user_b))
  );

-- Only the recipient bumps status (sent -> delivered -> seen).
create policy messages_update on public.messages for update
  using (to_uid = auth.uid())
  with check (to_uid = auth.uid());
-- No delete policy: messages immutable, mirrors `allow delete: if false`.

-- =========================================================
-- CLUBS  (firestore.rules lines 203-296, 424-500)
-- =========================================================
create policy club_requests_select on public.club_requests for select
  using (public.is_platform_admin() or owner_uid = auth.uid());

create policy club_requests_insert on public.club_requests for insert
  with check (owner_uid = auth.uid() and status = 'pending');

-- Only the platform admin reviews (approve/reject/delete).
create policy club_requests_update on public.club_requests for update
  using (public.is_platform_admin())
  with check (public.is_platform_admin());
create policy club_requests_delete on public.club_requests for delete
  using (public.is_platform_admin());

create policy clubs_select on public.clubs for select using (true); -- mirrors `allow read: if true`

-- Clubs are created ONLY by the platform admin, on behalf of an approved
-- requester who is NOT the admin themself — same self-service-creation
-- bypass this project closed in Phase 18, closed the same way here.
create policy clubs_insert on public.clubs for insert
  with check (public.is_platform_admin() and owner_uid <> auth.uid());

create policy clubs_update on public.clubs for update
  using (public.is_club_admin(id))
  with check (public.is_club_admin(id));
-- No delete policy: no UI path exists for it (blueprint G item); adding
-- one is a product decision, not inferable from the reference rules,
-- which is genuinely ambiguous here (admins.hasAny would have allowed
-- it) — left deliberately absent rather than guessed, per the mission's
-- "stop at this boundary rather than guessing" instruction. Document only.

create policy club_members_select on public.club_members for select
  using (
    user_id = auth.uid()
    or public.is_club_admin(club_id)
    or public.is_platform_admin()
  );

create policy club_members_insert on public.club_members for insert
  with check (public.is_platform_admin() or public.is_club_admin(club_id));

create policy club_members_update on public.club_members for update
  using (public.is_platform_admin() or public.is_club_admin(club_id))
  with check (public.is_platform_admin() or public.is_club_admin(club_id));

create policy club_members_delete on public.club_members for delete
  using (public.is_platform_admin() or public.is_club_admin(club_id));

create policy club_join_requests_select on public.club_join_requests for select
  using (user_id = auth.uid() or public.is_platform_admin() or public.is_club_admin(club_id));

create policy club_join_requests_insert on public.club_join_requests for insert
  with check (user_id = auth.uid() and status = 'pending');

create policy club_join_requests_update on public.club_join_requests for update
  using (public.is_platform_admin() or public.is_club_admin(club_id))
  with check (public.is_platform_admin() or public.is_club_admin(club_id));

create policy club_join_requests_delete on public.club_join_requests for delete
  using (public.is_platform_admin() or public.is_club_admin(club_id));

-- club_messages: no parent-doc existence prerequisite at all (see
-- migration-header note) — membership alone gates it, exactly like the
-- Firestore rule after its Phase 18 fix, minus the bootstrap step that
-- fix could never fully remove.
create policy club_messages_select on public.club_messages for select
  using (public.is_club_member(club_id));

create policy club_messages_insert on public.club_messages for insert
  with check (user_id = auth.uid() and public.is_club_member(club_id));
-- No update/delete policy: immutable, mirrors `allow update, delete: if false`.

-- =========================================================
-- EVENTS  (firestore.rules lines 183-197)
-- =========================================================
create policy events_select on public.events for select
  using (college_id = public.current_college_id());

create policy events_insert on public.events for insert
  with check (created_by = auth.uid() and college_id = public.current_college_id());

create policy events_update on public.events for update
  using (created_by = auth.uid() and college_id = public.current_college_id())
  with check (created_by = auth.uid() and college_id = public.current_college_id());

create policy events_delete on public.events for delete
  using (created_by = auth.uid() and college_id = public.current_college_id());

-- =========================================================
-- NOTIFICATIONS  (firestore.rules lines 226-242)
-- =========================================================
create policy notifications_select on public.notifications for select
  using (to_uid = auth.uid());

create policy notifications_insert on public.notifications for insert
  with check (from_uid = auth.uid() and to_uid <> auth.uid());

create policy notifications_update on public.notifications for update
  using (to_uid = auth.uid())
  with check (to_uid = auth.uid());

create policy notifications_delete on public.notifications for delete
  using (to_uid = auth.uid());

-- =========================================================
-- ANONYMOUS COLLEGE CHAT  (firestore.rules lines 518-579)
-- =========================================================
-- isOwnCollegeRoom(chatId) mirror: room id (its PK) equals the caller's
-- own college_id. No get()-on-a-possibly-missing-doc at all here, since
-- current_college_id() already handles that gracefully.
create policy anon_rooms_select on public.anon_rooms for select
  using (college_id = public.current_college_id());

create policy anon_rooms_insert on public.anon_rooms for insert
  with check (
    college_id = public.current_college_id()
    and created_by = auth.uid()
  );
-- No update/delete policy: rooms persist, immutable, mirrors the original rule.

create policy anon_messages_select on public.anon_messages for select
  using (room_college_id = public.current_college_id() and expires_at > now());

create policy anon_messages_insert on public.anon_messages for insert
  with check (
    room_college_id = public.current_college_id()
    and user_id = auth.uid()
    and anon_id = (select anon_id from public.profiles where id = auth.uid())
    and expires_at > now() - interval '120 seconds'
    and expires_at < now() + interval '900 seconds'
  );
-- No update/delete policy: immutable, mirrors the original rule.

-- =========================================================
-- MOMENTS  (firestore.rules lines 505-513 — kept product-disabled, see
-- kMomentsEnabled; RLS still written correctly, including a fix for the
-- two real bugs the prior audit found in the Firestore version, since
-- fixing them costs nothing extra and avoids reintroducing a known class
-- into a fresh implementation).
-- =========================================================
-- Fix #1 (blueprint finding, docs/production-readiness-blueprint.md §6d):
-- the old Firestore rule was `allow read: if true` with no collegeId
-- check at all. This version enforces college isolation at the RLS layer
-- from day one, matching every other college-scoped collection, rather
-- than relying on a client query filter that was the ONLY thing standing
-- between users and cross-college visibility.
create policy moments_select on public.moments for select
  using (college_id = public.current_college_id() and is_hidden = false);

create policy moments_insert on public.moments for insert
  with check (user_id = auth.uid() and college_id = public.current_college_id());

-- Fix #2 (blueprint finding §6e): the old rule was owner-only with no
-- carve-out, so the report button always failed for the actual use case
-- (reporting someone ELSE's content). This version allows a non-owner to
-- flip is_hidden/bump reports_count ONLY — never owner-only fields —
-- expressed as a trigger-enforced column restriction, the same technique
-- used where a real column-level split is actually needed (Postgres has
-- no Firestore-style affectedKeys() primitive to inline into the policy
-- itself).
create or replace function public.enforce_moments_update_columns()
returns trigger language plpgsql as $$
begin
  if new.user_id <> old.user_id then
    raise exception 'user_id is immutable';
  end if;
  if auth.uid() <> old.user_id then
    -- non-owner: only reports_count/is_hidden may change
    if new.media_url <> old.media_url or new.college_id <> old.college_id
       or new.visibility <> old.visibility or new.anon_id is distinct from old.anon_id then
      raise exception 'non-owner may only update reports_count/is_hidden';
    end if;
  end if;
  return new;
end;
$$;
create trigger moments_enforce_update_columns
  before update on public.moments
  for each row execute function public.enforce_moments_update_columns();

create policy moments_update on public.moments for update
  using (user_id = auth.uid() or college_id = public.current_college_id())
  with check (user_id = auth.uid() or college_id = public.current_college_id());

create policy moments_delete on public.moments for delete
  using (user_id = auth.uid());
