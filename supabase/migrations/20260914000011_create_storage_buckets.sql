-- Found live, on-device, immediately after the realtime fix (000010):
-- posting to the feed failed with StorageException(message: "Bucket not
-- found", statusCode: 404). lib/services/storage_service.dart and
-- lib/clubs/create_club_screen.dart reference five Storage buckets
-- (profile_photos, posts, moments, events, clubs) that this migration set
-- never created -- another step, like Realtime publication membership,
-- that creating tables and RLS policies does not imply.
--
-- Bucket visibility mirrors what the Dart client already assumes: every
-- call site uses storage.from(bucket).getPublicUrl(path) and renders that
-- URL directly (no signed-URL flow anywhere in the app), so all five are
-- created public here to match existing, already-ported behavior exactly
-- -- this migration does not change what any bucket exposes relative to
-- what the app was already built to expect.
--
-- One exception worth flagging explicitly rather than silently fixing:
-- the "clubs" bucket stores club_id_cards/<uploader_uid>_<ts>.jpg -- an ID
-- card photo submitted for admin review during club creation
-- (lib/clubs/create_club_screen.dart). A public bucket means that image is
-- fetchable by anyone with the URL, not just platform admins. No
-- storage.rules file exists in this repo to compare against a prior
-- Firebase access model, so there is no baseline to say this is a
-- regression -- but it is a real privacy exposure either way. Fixing it
-- properly means switching that admin-review screen to
-- createSignedUrl(...) and making this bucket private, which touches app
-- code beyond "create the missing bucket" and is out of scope for this
-- fix-the-404 migration. Flagged here and in the final report rather than
-- guessed at.
insert into storage.buckets (id, name, public)
values
  ('profile_photos', 'profile_photos', true),
  ('posts', 'posts', true),
  ('moments', 'moments', true),
  ('events', 'events', true),
  ('clubs', 'clubs', true)
on conflict (id) do nothing;

-- storage.objects has RLS enabled by default in every Supabase project;
-- with no policies at all, every bucket -- public flag or not -- denies
-- all reads/writes through the authenticated/anon API (public bucket flag
-- only short-circuits the CDN-fronted /object/public/* URL path, not
-- direct table access these policies gate). Policies below allow public
-- read (matching the public bucket flag) and restrict writes to the
-- owning user, inferred from the path convention each call site already
-- uses.

-- profile_photos: profiles/<uid>.jpg
create policy profile_photos_read on storage.objects for select
  using (bucket_id = 'profile_photos');

create policy profile_photos_write on storage.objects for insert
  with check (
    bucket_id = 'profile_photos'
    and name = 'profiles/' || auth.uid()::text || '.jpg'
  );

create policy profile_photos_update on storage.objects for update
  using (
    bucket_id = 'profile_photos'
    and name = 'profiles/' || auth.uid()::text || '.jpg'
  );

-- posts: posts/<uid>/<postId>.jpg
create policy posts_media_read on storage.objects for select
  using (bucket_id = 'posts');

create policy posts_media_write on storage.objects for insert
  with check (
    bucket_id = 'posts'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy posts_media_update on storage.objects for update
  using (
    bucket_id = 'posts'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- moments: moments/<uid>/<timestamp>.jpg
create policy moments_media_read on storage.objects for select
  using (bucket_id = 'moments');

create policy moments_media_write on storage.objects for insert
  with check (
    bucket_id = 'moments'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- events: events/<eventId>/<timestamp>.jpg -- not uploader-scoped by path;
-- any authenticated user may attach media (matches events_insert in
-- 20260914000002_rls_policies.sql, which lets any college member create
-- an event).
create policy events_media_read on storage.objects for select
  using (bucket_id = 'events');

create policy events_media_write on storage.objects for insert
  with check (bucket_id = 'events' and auth.uid() is not null);

-- clubs: club_id_cards/<uid>_<timestamp>.jpg -- see the public-exposure
-- note above. Left public-read for now to match the app's getPublicUrl
-- usage; write is still uploader-restricted.
create policy clubs_media_read on storage.objects for select
  using (bucket_id = 'clubs');

create policy clubs_media_write on storage.objects for insert
  with check (
    bucket_id = 'clubs'
    and split_part(storage.filename(name), '_', 1) = auth.uid()::text
  );
