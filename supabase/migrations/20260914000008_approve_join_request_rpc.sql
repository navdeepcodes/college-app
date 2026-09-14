-- Same reasoning as approve_club_request (20260914000007): the Firestore
-- version's runTransaction for approving a club_join_requests row (add
-- club_members, bump members_count, delete the request) needs a real
-- Postgres transaction, not three sequential PostgREST calls. Also not
-- SECURITY DEFINER -- runs as the caller, so club_members_insert's own
-- RLS (is_platform_admin() or is_club_admin(club_id)) still gates it.
create or replace function public.approve_club_join_request(p_request_id uuid)
returns void
language plpgsql
as $$
declare
  v_request record;
begin
  select * into v_request from public.club_join_requests where id = p_request_id for update;

  if not found then
    return;
  end if;

  insert into public.club_members (club_id, user_id, role)
    values (v_request.club_id, v_request.user_id, 'member');
  -- members_count bumps via the existing bump_club_members_count trigger.

  delete from public.club_join_requests where id = p_request_id;
end;
$$;

grant execute on function public.approve_club_join_request(uuid) to authenticated;
