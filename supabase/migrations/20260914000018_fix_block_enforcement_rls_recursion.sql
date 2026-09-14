-- Found immediately via live adversarial testing of the moderation
-- migration just added (20260914000017): the block-enforcement clause in
-- messages_insert/friend_requests_insert did a raw
-- `exists (select 1 from public.blocks b where ...)` inside the policy's
-- WITH CHECK. That subquery is itself subject to blocks' own RLS
-- (blocks_select: `blocker_uid = auth.uid() or is_platform_admin()`) --
-- evaluated as the INSERTING user. For the person being blocked (not the
-- blocker), that means the subquery can never see the very block row meant
-- to stop them, since blocks_select only lets the BLOCKER see it. The
-- policy's NOT EXISTS therefore always evaluated true from the blocked
-- user's side, and a real adversarial test proved it: C could still send B
-- a friend request immediately after B blocked C.
--
-- This is exactly the nested-RLS-recursion class 20260914000003 already
-- fixed for is_platform_admin()/is_club_admin() -- same fix shape: a
-- SECURITY DEFINER helper function, owned by the migration role (which
-- bypasses RLS on tables it queries, since RLS restricts other roles
-- acting on the table, not the owning role), so the block check itself is
-- no longer subject to blocks' own visibility policy.
create or replace function public.is_blocked_pair(uid_a uuid, uid_b uuid)
returns boolean
security definer set search_path = public, pg_temp
language sql stable
as $$
  select exists (
    select 1 from public.blocks b
    where (b.blocker_uid = uid_a and b.blocked_uid = uid_b)
       or (b.blocker_uid = uid_b and b.blocked_uid = uid_a)
  );
$$;
grant execute on function public.is_blocked_pair(uuid, uuid) to authenticated;

drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert
  with check (
    from_uid = auth.uid()
    and to_uid <> auth.uid()
    and exists(select 1 from public.conversations c where c.id = conversation_id and auth.uid() in (c.user_a, c.user_b))
    and not public.is_blocked_pair(from_uid, to_uid)
  );

drop policy if exists friend_requests_insert on public.friend_requests;
create policy friend_requests_insert on public.friend_requests for insert
  with check (
    from_uid = auth.uid()
    and to_uid <> auth.uid()
    and not public.is_blocked_pair(from_uid, to_uid)
  );
