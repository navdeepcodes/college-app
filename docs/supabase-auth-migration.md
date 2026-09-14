# TrueKinn — Supabase Auth Migration

## There is no existing user base to migrate

Confirmed, not assumed: the Firebase project TrueKinn's config files reference (`navdeep-college-app`, per `android/app/google-services.json`'s absence and `ios/Runner/GoogleService-Info.plist`'s `PROJECT_ID`) is not among the projects accessible from the Firebase account logged into this environment (`firebase projects:list` returns `Apostle`, `Huddle`, `Huddle Workspace` — none of them TrueKinn). This matches a finding from the prior "final pre-beta hardening" session. There is no real Firebase Auth user list this migration could export, and no real `friends`/`posts`/etc. data owned by real users. **Everything below is the process for when a real user base exists, not a migration this session needed to (or could) execute.**

## Identity model: Firebase UID → Supabase UUID

Firebase Auth UIDs are 28-character base62 strings assigned by Firebase; Supabase Auth uses standard UUIDs assigned by `auth.users`. These are different, non-overlapping identity spaces — there is no way to make a migrated user's Supabase UUID equal their old Firebase UID, and no reason to try. Every foreign key in the new schema (`profiles.id`, and everything that references it) is a UUID against `auth.users(id)`, not a preserved Firebase UID.

Practical consequence for the hardcoded platform admin: `firestore.rules`' `isAdmin()` checked a literal Firebase UID constant (`OImOQirOL7eQNftKASo4FTrF6XA3`, mirrored in `lib/core/admin.dart`). That exact value is meaningless in Supabase's identity space. The new schema replaces it with `profiles.is_admin boolean` (see `docs/supabase-schema.md`) — a flag the project owner sets once, by hand, on whichever real Supabase account should hold that role, once it exists. This migration cannot set it for them (there is no real admin account yet to set it on), and does not fabricate one.

## `auth.users` vs `public.profiles`

Supabase Auth's `auth.users` table (managed entirely by Supabase — email, password hash, OAuth identities, sessions) is never queried directly by app code or RLS policies in this schema; `public.profiles` is the public-facing profile row, one per `auth.users` row, created either by a client-side upsert (mirroring `auth_gate.dart`'s `_UserBootstrap` exactly — read-own-row, and if absent, insert) or, more robustly, a `handle_new_user()` trigger on `auth.users` that Supabase's own starter templates commonly use. **This migration did not decide between those two for you** — the Firestore reference implementation uses the client-side bootstrap pattern, and the live scenario test in this session used the equivalent (`profiles_insert` policy, `with check (id = auth.uid())`, exercised from the client's own session). A trigger-based bootstrap is a reasonable future improvement (removes one client round-trip and one class of "did the client's bootstrap write actually run" edge case) but changing to it is an architecture decision beyond what this migration's brief asked for — noted here, not silently done.

## Google Sign-In: a real, unavoidable manual step

TrueKinn's primary sign-in method is Google OAuth (`google_sign_in` package) — confirmed in a prior session to always talk to real Google servers regardless of any Firebase-emulator configuration, and the same is true for Supabase: Supabase Auth's Google provider requires a real Google Cloud OAuth 2.0 client ID/secret and an authorized redirect URI, configured in the Supabase dashboard's Authentication → Providers → Google settings, by the project owner. **This cannot be done from this session** — it requires the user's own Google Cloud Console and Supabase dashboard access, and is exactly the kind of credential this migration's own instructions forbid fabricating.

Until that's configured, Google Sign-In cannot be cut over to Supabase Auth. Email/password, by contrast, needs no such external configuration and could be cut over to Supabase Auth immediately if the product wanted an interim or alternative sign-in method — this migration did not build that cutover in Flutter this session (see `docs/supabase-migration-status.md` for why), but nothing blocks it the way Google Sign-In is blocked.

## College-gating and profile fields

`college_id_from_email()`, `profiles.college_id`, `profiles.anon_id`, `profiles.profile_completed` all carry over unchanged in meaning from their Firestore equivalents (see `docs/supabase-schema.md`), enforced the same way — by a trigger validating collegeId against the verified email on create, and immutability on update — just expressed as Postgres triggers instead of Firestore rule clauses. `profiles.anon_id` keeps its "mint once from NULL, then locked" semantics exactly.

## What a real migration, when one is eventually needed, should do

1. Export the Firebase Auth user list (`firebase auth:export`) — email, provider, UID, creation date. **Not password hashes** — Firebase does not export them in a usable form, and even if it did, re-hashing into Supabase's format without the plaintext is not possible. This is a real, unavoidable constraint, not a gap in this migration's effort.
2. For each exported user, create a matching `auth.users` row via the Supabase Admin API (`inviteUserByEmail` or `admin.createUser` with `email_confirm: true`), which issues a **password reset / magic link flow** rather than transplanting a password — this is the standard, correct answer to "how do existing users get into the new system," not a corner this migration is cutting.
3. Insert a matching `profiles` row per migrated user, preserving `college_id`, `anon_id`, `friends_count`, `profile_completed`, and `created_at` from their old Firestore `users/{uid}` document.
4. Migrate owned content (`posts`, `friendships`, etc.) referencing the OLD Firebase UID by rewriting the foreign key to the NEW Supabase UUID, using the mapping built in step 2 — this is why step 2 must fully complete, and be verified, before step 3 begins.
5. Communicate the re-authentication requirement to real users (an email/in-app notice: "we've upgraded our login system, please reset your password" or equivalent) — this is a product/communications decision, not an engineering one, and is called out here rather than assumed.

None of this was executed, because there is nothing to execute it against yet (Phase 0's finding). This section exists so the process is documented and ready, per this migration's own Phase 25 requirement, not because real data was on the line this session.
