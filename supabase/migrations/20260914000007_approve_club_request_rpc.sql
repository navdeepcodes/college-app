-- Found while porting admin_club_requests_screen.dart: Firestore's client
-- SDK could run a genuine multi-document transaction from the client
-- (runTransaction) -- re-read the request, bail if no longer pending,
-- atomically create clubs + club_members + flip club_requests.status.
-- PostgREST has no equivalent: each REST call from the Flutter client is
-- its own implicit transaction, so a naive port (three separate .insert/
-- .update calls in sequence) would reopen exactly the double-tap /
-- concurrent-approval race the Firestore transaction existed to close.
--
-- The correct replacement is a database function -- one Postgres
-- transaction, called once via supabase.rpc(). Deliberately NOT SECURITY
-- DEFINER: it runs as the CALLING user, so every insert/update inside
-- still passes through the normal RLS policies (clubs_insert,
-- club_members_insert, club_requests_update -- all of which already
-- require is_platform_admin()). A non-admin calling this gets denied by
-- RLS exactly as if they'd tried the three writes by hand; the function
-- only buys atomicity, not a privilege escalation.
create or replace function public.approve_club_request(p_request_id uuid)
returns uuid
language plpgsql
as $$
declare
  v_request record;
  v_club_id uuid;
begin
  select * into v_request from public.club_requests where id = p_request_id for update;

  if not found or v_request.status <> 'pending' then
    -- Already approved/rejected by a concurrent action -- no-op, matching
    -- the Firestore transaction's own early-return on this exact check.
    return null;
  end if;

  insert into public.clubs (name, description, owner_uid)
    values (v_request.club_name, v_request.description, v_request.owner_uid)
    returning id into v_club_id;

  insert into public.club_members (club_id, user_id, role)
    values (v_club_id, v_request.owner_uid, 'admin');

  update public.club_requests set status = 'approved' where id = p_request_id;

  return v_club_id;
end;
$$;

grant execute on function public.approve_club_request(uuid) to authenticated;
