-- Found during the hardening pass's storage-security audit (task H): the
-- `events` bucket's write policy, added in 20260914000011_create_storage_buckets.sql,
-- only checked `auth.uid() is not null` -- it never verified the eventId
-- segment of the upload path (`events/<eventId>/<timestamp>.jpg`) actually
-- corresponds to an event the caller owns. Any authenticated user, from any
-- college, could upload/overwrite media under ANY event's storage folder,
-- including events they don't own and events belonging to a different
-- college -- a real authorization gap, independent of whether the current
-- UI happens to expose event-media upload (it doesn't yet; RLS is the
-- boundary regardless of client reachability, not client code paths).
--
-- lib/services/storage_service.dart's uploadEventMedia() always uploads to
-- an eventId it just created itself in the same flow, so tightening this to
-- require created_by = auth.uid() on the target event matches the only
-- legitimate usage and breaks nothing real.
drop policy if exists events_media_write on storage.objects;

create policy events_media_write on storage.objects for insert
  with check (
    bucket_id = 'events'
    and exists (
      select 1 from public.events e
      where e.id::text = (storage.foldername(name))[2]
        and e.created_by = auth.uid()
    )
  );
