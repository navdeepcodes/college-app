-- Beta-hardening mission, item 12 ("STORAGE SECURITY"): the clubs bucket
-- was created public in 20260914000011_create_storage_buckets.sql,
-- explicitly flagged there as a known, unfixed exposure -- club ID card
-- photos (a personal document) were fetchable by anyone with the URL,
-- not just the admins reviewing the request. Fixing it now, as instructed.
--
-- lib/clubs/create_club_screen.dart now stores the storage PATH in
-- club_requests.id_card_url instead of a public URL, and
-- lib/clubs/admin_club_requests_screen.dart resolves that path into a
-- short-lived signed URL (5 min) on demand when an admin opens the
-- review screen -- never persisted, never shown to anyone else. Existing
-- rows in club_requests.id_card_url predate this change and hold public
-- URLs, not paths; they were synthetic scenario-test rows ("https://x/id.jpg"),
-- not real data, so no backfill was needed -- confirmed by querying the
-- table directly before writing this migration.

update storage.buckets set public = false where id = 'clubs';

drop policy if exists clubs_media_read on storage.objects;

-- Read is now restricted to the uploader (the club-creation applicant,
-- so they can still see their own submission if the UI ever shows it
-- back to them) or a platform admin (the actual reviewer). Everyone else
-- -- including other authenticated users and anon -- is denied, matching
-- the fact that an ID card photo is not campus-public content the way a
-- feed post or event flyer is.
create policy clubs_media_read on storage.objects for select
  using (
    bucket_id = 'clubs'
    and (
      split_part(storage.filename(name), '_', 1) = auth.uid()::text
      or public.is_platform_admin()
    )
  );

-- clubs_media_write (insert) from 20260914000011 is unchanged: uploader-
-- restricted by the same filename-prefix check, still correct.
