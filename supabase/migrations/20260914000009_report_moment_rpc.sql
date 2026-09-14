-- Firestore's client-side FieldValue.increment(1) has no PostgREST
-- equivalent for an atomic column bump via .update() -- a naive port
-- (read reports_count, add 1, write it back) would race under concurrent
-- reports. This RPC does the increment and the >=3 auto-hide check as one
-- atomic statement. Runs as the caller (not security definer), so it
-- still passes through moments_update's RLS -- specifically the
-- enforce_moments_update_columns trigger fix (see
-- 20260914000002_rls_policies.sql) that makes a non-owner's
-- reports_count/is_hidden-only update actually succeed, unlike the
-- original Firestore rule (owner-only, no carve-out -- the exact bug this
-- migration fixed ahead of the reference implementation). Moments stays
-- product-disabled; this exists so the fix is real and complete, not
-- half-done, whenever a future session reconsiders re-enabling it.
create or replace function public.report_moment(p_moment_id uuid)
returns integer
language plpgsql
as $$
declare
  v_count integer;
begin
  update public.moments
    set reports_count = reports_count + 1
    where id = p_moment_id
    returning reports_count into v_count;

  if v_count is not null and v_count >= 3 then
    update public.moments set is_hidden = true where id = p_moment_id;
  end if;

  return v_count;
end;
$$;

grant execute on function public.report_moment(uuid) to authenticated;
