# TrueKinn — Supabase Migration Plan

**Status as of this document: Phases 0–3 executed and live-verified against a real Supabase project. Phases 4–25 not started — see docs/supabase-migration-status.md for the exact boundary and why.**

## Phase 0 — Baseline (frozen before any change)

Verified state of the Firebase implementation immediately before this migration began (same session, same day, no drift):

- `flutter analyze`: 0 issues
- `flutter test`: 32/32
- Firestore rules: 211/211 passing (`functions/test-rules/*.test.js`, 6 files)
- 47-step chained multi-account scenario: passing
- `git log`: `HEAD` at `a46ea7f`, 4 commits ahead of a previously-pushed `origin/main` at `55be496`

### Firestore collections (18, from `firestore.rules`)
`users`, `posts`, `posts/likes`, `posts/comments`, `events`, `club_requests`, `notifications`, `club_members`, `club_join_requests`, `chats`, `chats/messages`, `friends`, `friend_requests`, `club_chats`, `club_chats/messages`, `clubs`, `clubs/posts`, `moments`, `anon_chats`, `anon_chats/messages`.

### Cloud Functions (2, from `functions/index.js`)
- `cleanupExpiredAnonMessages` — scheduled, every 1 minute, deletes expired `anon_chats/*/messages`.
- `friendCreated` — Firestore trigger on `friends/{friendId}` create, bumps `friendsCount` on both members' `users` docs (server-side, since a client can't write a peer's doc under the `users` rule).

### Firebase Auth usage
`firebase_auth: ^5.3.0`. Google Sign-In is the primary method (`google_sign_in` package, always talks to real Google servers — confirmed in a prior session, this is why the Firebase Emulator Suite could never be used to test the real sign-in flow). Email/password exists at the SDK level but the app's UI (`welcome_screen.dart`, `login_screen.dart`, `signup_screen.dart`) — not re-audited in this pass beyond confirming the package is Google-first.

### Files touching `firebase_auth` / `cloud_firestore` directly
35 files under `lib/` (grep count). Full list not reproduced here; see `grep -rl "firebase_auth\|cloud_firestore" lib/` for the current, authoritative list — it will drift as work proceeds, so this document doesn't freeze a stale copy of it.

### Existing Supabase usage (pre-migration)
`supabase_flutter: ^2.5.0`, used for Storage only: `lib/moments/moment_camera_screen.dart`, `lib/clubs/create_club_screen.dart`, `lib/auth/screens/profile_setup_page.dart`, `lib/services/storage_service.dart`. `lib/main.dart` calls `Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey)` — **at the start of this session `lib/secrets.dart` held only placeholder values** (`https://placeholder.supabase.co`), confirmed by reading the file directly — the app was not actually wired to any live Supabase project before this migration began.

### Real user data
**None.** The Firebase project this app was built against (`navdeep-college-app`, referenced in `google-services.json`/`GoogleService-Info.plist`) is not accessible from the Firebase account available in this environment (`firebase projects:list` returns 3 unrelated projects, not this one) — confirmed in the prior "final pre-beta hardening" session and re-confirmed here. There is no real Firebase Auth user base to migrate. This substantially de-risks Phase 18 (data migration) and most of `docs/supabase-auth-migration.md`'s "existing user" concerns: they're a documented *process* for when real users exist, not an actual migration this session needed to run.

## Phase 1 — Supabase project

The user provided a Supabase Personal Access Token and named the target project **"ReServe dev"** (ref `nczagxcixactkskqhjll`, org `ekembbjaczdqaswrvwsn`, region South Asia/Mumbai). It was found **paused** (Supabase auto-pauses inactive free-tier projects) and was restored via the Management API (`POST /v1/projects/{ref}/restore`) before any further work — confirmed `ACTIVE_HEALTHY` before proceeding.

**Critical finding before touching anything:** the project was not empty. It already had a `public` schema with `food_posts` and `users` tables — an unrelated, pre-existing app (apparently the project's original "ReServe" purpose), not TrueKinn data. This was flagged to the user explicitly (not assumed) because of one direct, structural collision: TrueKinn's own migration needs a `users`/`profiles` table, and Supabase Auth (`auth.users`) is inherently shared across whatever uses a given project — building TrueKinn straight into `public` without checking first risked either a naming collision or silently mixing two unrelated apps' user bases. **The user confirmed this project is disposable** and authorized wiping it. `supabase/migrations/20260914000000_drop_legacy_reserve_schema.sql` drops exactly those two tables, as its own isolated, auditable migration step — nothing else in the project was touched.

## Phase 1 — Schema

See `docs/supabase-schema.md` for the full table-by-table reference. Summary: 18 Firestore collections → 18 Postgres tables, applied via `supabase/migrations/20260914000001_initial_schema.sql`. Every table, function, and trigger is documented inline in that file with a comment citing the exact `firestore.rules` block or prior-session bug it replaces or improves on.

Deliberate normalizations (not literal document→JSON-blob copies, per this migration's own instruction to prefer relational modeling):
- `chats`/`friends`' sorted-pair document IDs → `CHECK (user_a < user_b)` + `UNIQUE(user_a, user_b)` table constraints. This is not a cosmetic change: it converts the exact bug class that broke ~50% of new 1:1 chats in Phase 18 of the Firebase hardening work (a client convention the create *rule* checked, but real client code initially got wrong) into something no write path can get wrong, because the database itself won't accept an unsorted pair.
- `clubs.admins` array → derived from `club_members.role = 'admin'`, a single source of truth instead of two fields that could drift apart.
- `club_chats/{clubId}` parent document → no parent-row equivalent needed at all. `club_messages.club_id` is a plain foreign key. Firestore's version needed that parent document to exist before its subcollection was reachable — its total absence was a real, total-outage bug (Phase 18). A foreign key has no such prerequisite-row requirement; the entire bug class is structurally impossible here.
- `likesCount`/`commentsCount`/`friendsCount`/`membersCount` → maintained by `AFTER INSERT/DELETE` triggers, not client-issued `FieldValue.increment()` calls the rules merely permitted. Verified live (see Phase 3 below) that these fire correctly and atomically for a non-owner actor (e.g., B liking A's post correctly bumps A's post's `likes_count`).

## Phase 2 — Auth migration design

See `docs/supabase-auth-migration.md`. Summary: Supabase Auth's `auth.users` is the identity source of truth (never mirrored/duplicated); `public.profiles.id` is a foreign key to it, not a separate mirrored `uid` field the way Firestore's `users/{uid}.uid` field duplicated the document ID. Google Sign-In requires the user to add real OAuth client credentials to the Supabase dashboard's Auth provider settings before that path can be cut over — a real, unavoidable manual step, not fabricated or worked around. Email/password needs no such dashboard step and could be cut over immediately if desired. No password migration is attempted or needed, because there is no existing Firebase user base to migrate (see Phase 0 above) — the document instead specifies the process for if/when one exists.

## Phase 3 — RLS security model

See `docs/supabase-security-model.md` for the full block-by-block mapping from `firestore.rules` to `supabase/migrations/20260914000002_rls_policies.sql`. Every `allow read/create/update/delete` clause in the 20 Firestore `match` blocks has a cited Postgres RLS `policy` equivalent.

### Live verification (not just design)

`supabase/tests/rls_scenario_check.py` replays the same shape of chained, realistic, multi-account sequence as `functions/test-rules/scenario_walkthrough.test.js` did for Firestore — but against the **real** live project, using **real** Supabase Auth accounts (created via the Admin API) and **real** signed session JWTs from an actual password sign-in (not hand-crafted tokens), calling the real PostgREST REST API exactly the way the Flutter client eventually will. Three synthetic accounts (A/B at NMIT, C at RVCE), 40 steps: profile bootstrap, feed post/like (college-isolated), friend request/accept (consent check, duplicate-request prevention), 1:1 chat (sender-spoofing denial), full club lifecycle (self-service-creation denial, join approval, the Phase-21-equivalent "read your own nonexistent membership row" case), anonymous college chat (college isolation, TTL bound), events (college isolation), notifications (recipient-only read). **All 40 passed** on the final run.

Two real, live-only bugs were found and fixed in the process — neither would have been caught by schema/policy review alone, exactly the lesson this whole project has learned the hard way on the Firestore side:

1. **RLS helper recursion** (`supabase/migrations/20260914000003_fix_rls_helper_recursion.sql`): `current_college_id()`, `is_platform_admin()`, `is_club_member()`, `is_club_admin()` each query a table whose OWN RLS policy calls that same helper — infinite recursion, surfaced as `stack depth limit exceeded` the moment any real write exercised one. Fixed with the standard Postgres/Supabase pattern: `SECURITY DEFINER` with a pinned `search_path` on the helper, so its internal lookup bypasses RLS for that one query only (not a general bypass for the caller) — the same property Firestore's `get()` inside a rule already had for free, which `SECURITY INVOKER` (the default) had silently lost.
2. **Counter-trigger RLS blocking**: the same migration also applies `SECURITY DEFINER` to `bump_post_likes_count`, `bump_post_comments_count`, `bump_friends_count`, and `bump_club_members_count` — each updates a row belonging to someone OTHER than the acting user (e.g. B liking A's post needs to update A's post), which the target table's own `UPDATE` policy would otherwise block. `bump_conversation_last_message` was deliberately left as the default (`SECURITY INVOKER`) after checking it doesn't need the fix: the message sender is always a conversation participant, and `conversations_update` already permits either participant — applying `SECURITY DEFINER` there would have been an unnecessary, unjustified widening of trust boundary.

## What this phase deliberately did NOT do

Per the mission's own Phase 19 ("dual-backend safety... transitional... Firebase implementation → Supabase implementation → tests → verification → switch → remove old implementation") and Phase 16 ("only AFTER the Supabase implementation is working and verified: remove Firebase"): the Flutter app itself has **not** been cut over. `lib/` still runs entirely on Firebase; nothing in this phase changed app runtime behavior. This is a deliberate checkpoint, not an oversight — see `docs/supabase-migration-status.md` for the full accounting of what's done, what's next, and why stopping here (with a real, live-verified backend, not a paper plan) was the responsible boundary for this session.
