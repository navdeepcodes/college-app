# TrueKinn — Supabase Migration: Final Report

This report supersedes the version written after Phase 1 (backend-only).
Everything below reflects the actual current state: **the full Flutter
cutover happened, Firebase has been removed, and the app has been built,
installed, and live-tested on a real Android device against the real
Supabase project** — none of which was true when the earlier version of
this document was written.

## Original architecture (at session start)

Firebase Auth (Google Sign-In primary) + Cloud Firestore (18 collections)
+ Firestore Security Rules (582 lines, 20 match blocks, 211 passing
tests) + 2 Cloud Functions.

## Final architecture (current)

**Supabase only. Firebase is fully removed, not just superseded.**

- Auth: Supabase Auth (email/password verified live end-to-end; Google
  via `signInWithIdToken`, code-complete, blocked on a dashboard config
  step only a human can do — see Remaining blockers).
- Data: Postgres, 18 tables, full RLS (`supabase/migrations/000000`–`000011`).
- Storage: 5 buckets (`profile_photos`, `posts`, `moments`, `events`,
  `clubs`), created and RLS-gated in `20260914000011_create_storage_buckets.sql`.
- Realtime: all 16 tables the Flutter app subscribes to via `.stream()`
  are in the `supabase_realtime` publication (`20260914000010_enable_realtime.sql`).
- `firebase_core`, `firebase_auth`, `cloud_firestore` are gone from
  `pubspec.yaml`; `lib/firebase_options.dart` and `lib/core/admin.dart`
  are deleted; `grep -rl "firebase_auth\|cloud_firestore" lib/` returns
  nothing. The native Android `google-services` Gradle plugin is removed
  (nothing left to apply it to, and its presence would otherwise require
  a `google-services.json` that never existed).
- `firestore.rules`, `functions/`, and `functions/test-rules/*.test.js`
  (211 tests) are deliberately left in place as reference/security-
  behavioral documentation — not deleted, not used by the running app.

## What changed since the last report (Phases 8–11)

The Phase-1 report described "backend built, Flutter unchanged." Since
then, in order:

- **Phase 8**: full Flutter cutover — every feature (auth, feed, friends,
  chat, anon chat, clubs, notifications, settings, moments) rewritten
  against Supabase. Firebase removed from the Dart dependency graph.
- **Phase 9**: first-ever successful native Android build, install, and
  launch for this project (previously blocked every prior session on a
  missing `google-services.json`) — unblocked by removing the now-dead
  `google-services` plugin. Live on-device signup and login were tested;
  login surfaced a real race condition (`profiles_pkey` unique violation
  when two `AuthGate` instances bootstrap concurrently), root-caused via
  direct DB timestamp correlation, and fixed.
- **Phase 10**: live-testing the fixed login uncovered that **Realtime
  was never enabled for any table** — every `.stream()`-backed screen
  (feed, chat, clubs, notifications, friends, comments, moments, events)
  failed outright the moment it was opened. Fixed by adding all 16
  tables to `supabase_realtime`.
- **Phase 11**: with Realtime fixed, the next live test (creating a real
  feed post) immediately hit two more bugs: **no Storage buckets existed
  at all** (404 on first upload), and once that was fixed, the post
  insert failed RLS because **`canonicalCollegeId()` read Firestore's
  camelCase `collegeId` field, which is never present on a Postgres row**
  — it silently fell through to the human-readable `college` display
  string instead of the canonical `college_id` slug every RLS policy and
  Realtime filter compares against. Both fixed; verified end-to-end by
  posting a real image with a real caption and watching it render back
  through the Realtime stream.

**The throughline worth stating plainly**: all four of these were found
by literally opening the running app and using it, not by the automated
RLS scenario test — which stayed green through all of it (see Test
results below). That test validates the security model; it does not
exercise the Dart client at all. A backend can be perfectly correct and
the app can still be completely broken. This is why "the schema and RLS
tests pass" was never treated as sufficient evidence of readiness this
session.

## Complete schema

See `docs/supabase-schema.md` (schema-level; storage buckets and the
Realtime publication are the two additions from Phases 10–11 not yet
reflected there — see the migration files themselves for the current
source of truth: `supabase/migrations/`).

## Feature migration + live-verification status

| Feature | Cut over to Supabase | Live on-device verification |
|---|---|---|
| Auth (signup, login, race-condition fix) | yes | **yes** — real signup, real login, race condition found and fixed live |
| Profile setup / completion | yes | **yes** — full form submit verified, `profile_completed` flag confirmed written |
| Feed (read, college-scoped) | yes | **yes** — confirmed broken (missing Realtime + wrong college_id), then confirmed fixed |
| Feed (create post: storage + insert) | yes | **yes** — real image uploaded, real row inserted, rendered back live |
| Profile screen (own profile, posts grid, counts) | yes | **yes** — `posts_count` trigger confirmed correct |
| Search (classmate search) | yes | **yes** — confirmed working, no errors |
| Events (college-scoped read) | yes | **yes** — confirmed working, real pre-existing event rendered |
| Clubs (Your Clubs / Explore tabs) | yes | partial — screen loads and streams cleanly; create/approve/join not exercised on-device this session |
| Messages / 1:1 chat list | yes | partial — list screen loads cleanly; sending/receiving a message not exercised on-device this session |
| Friends (request/accept) | yes | not exercised on-device this session (RLS-scenario-tested only, see caveat above) |
| Anonymous college chat | yes | not exercised on-device this session (RLS-scenario-tested only) |
| Notifications | yes | not exercised on-device this session (RLS-scenario-tested only) |
| Club chat, moderation/report flows | yes | not exercised on-device this session (RLS-scenario-tested only) |
| Moments | yes (code cut over) | **intentionally not tested** — `kMomentsEnabled = false`, untouched per standing instruction |

## Security / RLS status

Complete. 40/40 scenario-test steps pass on the current full schema
(migrations 000000–000011), re-run this session after the storage/
realtime/college_id fixes to confirm no regression. Full mapping in
`docs/supabase-security-model.md` (schema-level content still accurate;
does not yet cover storage.objects policies — see
`20260914000011_create_storage_buckets.sql` directly for those).

## Storage status

**Built and live-verified this session** (Phase 11). All 5 buckets
created with RLS matching the app's existing upload-path conventions.
One open item, not fixed: the `clubs` bucket (club-creation ID card
photos) is public-read to match the app's existing `getPublicUrl()`
usage everywhere, which means an ID card image is fetchable by anyone
with the URL, not just admins reviewing the request. Fixing this
properly needs a signed-URL flow in the admin review screen — flagged,
not fixed, since it's an app-code change beyond "create the missing
bucket."

## Realtime status

**Built and live-verified this session** (Phase 10). All 16
`.stream()`-backed tables are in the `supabase_realtime` publication.
RLS applies to the realtime changefeed the same as REST.

## Firebase removal status

**Done**, both layers:
- Dart: `firebase_core`/`firebase_auth`/`cloud_firestore` removed from
  `pubspec.yaml`, `firebase_options.dart` deleted, zero remaining
  imports anywhere in `lib/` (grep-verified).
- Native Android: `google-services` Gradle plugin removed from both
  `android/app/build.gradle.kts` and `android/settings.gradle.kts`.
- `firestore.rules` and `functions/` remain in the repo as reference
  material only, per the migration's own instruction not to discard the
  security-behavioral knowledge encoded in them.

## Test results

- `flutter analyze`: 0 issues at every checkpoint this session, including
  after each of the Phase 9–11 fixes.
- `supabase/tests/rls_scenario_check.py`: **40/40 passing**, re-run this
  session against the full current migration state (000000–000011) with
  freshly created test accounts, confirming no regression from the
  profile-fields/posts-count/RPC/realtime/storage migrations added since
  the last time this test ran.
- Real Android build: `BUILD SUCCESSFUL`, installed via `adb install -r`,
  launched on the `Aegis_Test` emulator.
- Real on-device testing performed this session: signup, login (including
  the race-condition fix), profile setup and completion, feed load
  (confirmed broken, then confirmed fixed), post creation (image upload
  + insert, confirmed broken twice — storage then RLS — then confirmed
  fixed and rendering live), classmate search, own-profile view with
  live post count, events list, clubs tabs, messages list.
- iOS: **not touched or re-verified this session.**

## Android / iOS results

Android: real build/install/launch verified this session, on real
hardware emulation, with real backend calls — not a compile-only check.

iOS: unchanged from before this session. Not attempted.

## Remaining blockers

1. **Google OAuth provider** must be configured in the Supabase dashboard
   by the project owner before Google Sign-In can be cut over (real
   credential, cannot be fabricated). Email/password has no such
   blocker and is already live-verified.
2. **iOS** has not been touched at all in this phase — no build attempt,
   no dependency resolution check, nothing. Treat it as unverified, not
   as "probably fine because Android is fine" — this session's own
   findings (three bugs Android live-testing caught that RLS testing
   missed) are a direct argument against assuming platform parity
   without separately testing it.
3. **Friends, 1:1 chat send/receive, clubs create/approve/join, club
   chat, anon chat, notifications, and moderation/report flows** are cut
   over and RLS-scenario-tested, but not exercised through the actual
   running app this session. Given this session's own pattern (every
   bug found was invisible to the scenario test and only surfaced by
   actually using the screen), these should be treated as unverified in
   practice until someone opens each screen and uses it.
4. **`clubs` storage bucket public-read exposure** (ID card photos) —
   documented above, not fixed.

## Remaining technical debt

- `clubs` table has no DELETE policy (pre-existing, documented gap) — a
  product decision, not an oversight.
- `comments` RLS was designed by direct parity with `post_likes` but
  isn't independently exercised in the scenario test.
- `docs/supabase-schema.md` and `docs/supabase-security-model.md` are
  schema/RLS-level references and are still accurate for that scope, but
  neither has been updated to include the storage buckets or the
  Realtime publication membership added in Phases 10–11.

## Final status

**INTERNAL TEST READY.**

Not CLOSED BETA READY: several core flows (friends, chat send, club
admin actions, anon chat, notifications, moderation) are cut over and
RLS-verified but not yet proven by actually using them, and iOS hasn't
been touched at all this phase. Given how many real, user-facing-breaking
bugs turned up in the flows that *were* live-tested — a race condition,
Realtime entirely non-functional, Storage entirely non-functional, and a
silent college-identity mismatch that would have corrupted every
college-scoped read and write in production — it would be dishonest to
call the untested flows "probably fine."

Not still MIGRATION IN PROGRESS either: the cutover is genuinely
complete (Firebase fully removed, not coexisting), the app builds and
runs on a real device against the real backend, and the flows that have
been tested work correctly end-to-end, including storage uploads and
real-time updates.

INTERNAL TEST READY is the honest middle: put this in front of a small
group of real users on Android, watch what breaks, and treat every
report from an untested flow as expected, not surprising.
