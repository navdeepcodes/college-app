-- Minimum viable moderation surface for the hardening pass (task I): the
-- readiness report found NO reachable reporting or user-blocking mechanism
-- anywhere in the app (the only report_* RPC, report_moment, lives entirely
-- inside the disabled Moments feature). This is the one missing safety
-- surface that matters before a beta goes beyond a small trusted group.
--
-- Scope deliberately kept minimal per the hardening brief: report a
-- post/user/message, block a user, block enforcement on the two highest-
-- value interaction surfaces (1:1 messages and friend requests), and
-- admin-only visibility into open reports. Not a full moderation platform
-- (no per-content auto-hide thresholds, no appeals flow, no report
-- categories beyond a free-text reason) -- those are real product
-- decisions this pass isn't the place to make unilaterally.

-- =========================================================
-- REPORTS
-- =========================================================
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_uid uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('post', 'comment', 'message', 'club_message', 'user', 'anon_message')),
  target_id uuid not null,
  reason text not null check (length(trim(reason)) > 0),
  details text,
  status text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now(),
  -- One report per (reporter, exact target) -- a double-tap or repeated
  -- "Report" taps on the same post must not spam duplicate rows; the
  -- reporter can still report a DIFFERENT piece of content from the same
  -- author, this only dedupes the identical target.
  unique (reporter_uid, target_type, target_id)
);
create index reports_status_idx on public.reports (status, created_at desc);

alter table public.reports enable row level security;

-- Reporters can only ever file a report as themselves -- never forge
-- another user's reporter_uid the way a malicious client might try.
create policy reports_insert on public.reports for insert
  with check (reporter_uid = auth.uid());

-- A reporter can see their own filed reports (so the UI can show "already
-- reported"); a platform admin can see everything, matching the brief's
-- "admin/moderator visibility of reports" requirement. Nobody else can read
-- another user's reports -- that would itself be a privacy leak.
create policy reports_select on public.reports for select
  using (reporter_uid = auth.uid() or public.is_platform_admin());

-- Only a platform admin can transition status (reviewed/dismissed) -- a
-- malicious client must not be able to dismiss/hide reports about their
-- own content by calling the API directly.
create policy reports_update on public.reports for update
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

-- No delete policy at all: reports are a moderation audit trail, not a
-- reporter-revocable action -- nobody (not even the reporter, not even an
-- admin) should be able to make a filed report disappear outright, only
-- transition its status via the update policy above.

-- =========================================================
-- BLOCKS
-- =========================================================
create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_uid uuid not null references public.profiles(id) on delete cascade,
  blocked_uid uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (blocker_uid <> blocked_uid),
  unique (blocker_uid, blocked_uid)
);

alter table public.blocks enable row level security;

-- Only ever create a block row as yourself, targeting someone else.
create policy blocks_insert on public.blocks for insert
  with check (blocker_uid = auth.uid() and blocked_uid <> auth.uid());

-- You can see who YOU blocked (to render "Unblock" in your own settings),
-- and a platform admin can see all block relationships for moderation
-- context. Deliberately NOT visible to the blocked party -- a block is not
-- an announcement, matching how blocking works on virtually every platform
-- this pattern is borrowed from.
create policy blocks_select on public.blocks for select
  using (blocker_uid = auth.uid() or public.is_platform_admin());

-- Only the blocker can remove their own block -- the blocked party must
-- never be able to unblock themselves via a direct API call, which is
-- exactly the escalation the hardening brief calls out by name.
create policy blocks_delete on public.blocks for delete
  using (blocker_uid = auth.uid());

-- =========================================================
-- BLOCK ENFORCEMENT: the two highest-value interaction surfaces
-- =========================================================
-- "Prevent blocked users from interacting where appropriate" -- 1:1
-- messaging and friend requests are the two surfaces where an unwanted
-- interaction is most directly harassing; RLS is the enforcement boundary,
-- not client-side hiding of a "Message"/"Add Friend" button (which a
-- modified or direct-API client would simply ignore).

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert
  with check (
    from_uid = auth.uid()
    and to_uid <> auth.uid()
    and exists(select 1 from public.conversations c where c.id = conversation_id and auth.uid() in (c.user_a, c.user_b))
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_uid = from_uid and b.blocked_uid = to_uid)
         or (b.blocker_uid = to_uid and b.blocked_uid = from_uid)
    )
  );

drop policy if exists friend_requests_insert on public.friend_requests;
create policy friend_requests_insert on public.friend_requests for insert
  with check (
    from_uid = auth.uid()
    and to_uid <> auth.uid()
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_uid = from_uid and b.blocked_uid = to_uid)
         or (b.blocker_uid = to_uid and b.blocked_uid = from_uid)
    )
  );
