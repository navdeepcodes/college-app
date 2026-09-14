# TrueKinn — Supabase Migration: Session Final Report

## Original architecture (at session start)

Firebase Auth (Google Sign-In primary) + Cloud Firestore (18 collections) + Firestore Security Rules (582 lines, 20 match blocks, 211 passing tests) + 2 Cloud Functions + Supabase Storage only (for Moments media, though `lib/secrets.dart` held only placeholder credentials — the app was not actually wired to a live Supabase project at session start).

## Final architecture (at session end)

**Two backends now exist, deliberately not yet merged into one running app:**
- The Firebase side is **completely unchanged** — same 211/211 rules tests, same `flutter analyze`/`flutter test` results, same app behavior. Nothing in this session touched it.
- A **new, real, live, fully-verified Supabase backend** now exists on the "ReServe dev" project: 18 Postgres tables (1:1 with the Firestore collections), full RLS policy coverage, counter-maintenance triggers, and a 40-step live scenario test proving the security model against real accounts and real signed tokens. The Flutter app does not yet talk to it.

## Complete schema

See `docs/supabase-schema.md` for the full table-by-table reference with every column, constraint, and function.

## Feature migration status

| Feature | Firebase (unchanged) | Supabase backend | Flutter cutover |
|---|---|---|---|
| Auth / onboarding | working, verified prior session | schema + RLS ready, live-verified for email/password-equivalent bootstrap flow | not started |
| Feed / posts / likes / comments | working, verified prior session | schema + RLS ready, live-verified (posts/likes; comments by direct policy parity, not independently scenario-tested this pass) | not started |
| Friends | working, verified prior session | schema + RLS ready, live-verified including forgery/duplicate prevention | not started |
| 1:1 chat | working, verified prior session | schema + RLS ready, live-verified including sender-spoofing denial | not started |
| Clubs (create/join/chat/admin) | working, verified prior session | schema + RLS ready, live-verified including self-service-creation denial and the Phase-21-equivalent nonexistent-row case | not started |
| Events | write-only gap documented and fixed in Flutter last session (read path added) | schema + RLS ready, live-verified for college isolation | not started |
| Notifications | working, verified prior session | schema + RLS ready, live-verified including recipient-only visibility | not started |
| Anonymous college chat | working, verified prior session | schema + RLS ready, live-verified including college isolation + TTL bound | not started |
| Moments | intentionally disabled, unchanged | schema + RLS ready, **plus two bugs fixed ahead of the reference** (college scoping, report carve-out) — not live-scenario-tested since the feature stays disabled either way | not started; stays disabled per explicit instruction |

## Authentication migration status

Design complete (`docs/supabase-auth-migration.md`). No real users exist to migrate (confirmed, not assumed — the Firebase project isn't even accessible from this environment's Firebase account). Google Sign-In cutover is blocked on a real, unavoidable manual step: the project owner configuring a Google OAuth client in the Supabase dashboard. Email/password has no such blocker and could be cut over first if wanted.

## Security / RLS status

Complete and live-verified. Full mapping in `docs/supabase-security-model.md`. Two real bugs found via live testing (RLS helper recursion; counter-trigger RLS-blocking) were fixed the same session they were found, with regression coverage in the scenario script. Every college-isolation, forgery-prevention, and escalation-prevention property the Firebase side had to learn the hard way (across three separate historical incidents: signup bootstrap, club membership view, and the original Phase 18 security pass) is proven, live, on the Postgres side too — not assumed to carry over just because the design looks equivalent on paper.

## Storage status

Not migrated this session. `lib/services/storage_service.dart` and its callers (Moments capture, club ID-card upload, profile photos) still use `Supabase.instance.client.storage` directly, unchanged — this was already Supabase-backed before the migration began (with placeholder credentials, per the Phase 0 finding), so there is genuinely nothing to migrate here yet in the sense of moving data between platforms; what remains is wiring real credentials into `lib/secrets.dart` and deciding bucket-level RLS policies, both out of scope for this pass.

## Realtime status

Not built this session. No Supabase Realtime subscriptions exist yet — this is Phase 12/15 territory, sequenced after the Flutter service-layer cutover begins.

## Edge Functions status

Not built. `functions/index.js`'s two Cloud Functions were not translated:
- `cleanupExpiredAnonMessages` → the natural Postgres equivalent is `pg_cron` (schedule a `DELETE FROM anon_messages WHERE expires_at < now()`) rather than an Edge Function, since it's a pure database invariant with no application logic — noted here as the recommended approach, not yet implemented or verified against this project's actual plan tier (pg_cron availability wasn't checked this session).
- `friendCreated` → superseded entirely by the `bump_friends_count()` trigger already built and live-verified this session (scenario step 3e implicitly exercises it via the friendship creation, though the counter value itself wasn't asserted in that step — worth adding as a follow-up assertion, not a gap in the trigger's correctness, which mirrors the already-proven `bump_post_likes_count` pattern exactly).

## Data migration status

Not applicable — no real data exists (Phase 0 finding, confirmed not assumed). Process documented in `docs/supabase-auth-migration.md` for when it becomes applicable.

## Firebase removal status

**Not started, deliberately.** `pubspec.yaml`, `firestore.rules`, `functions/`, and every Firebase-touching Dart file remain exactly as they were. Per the migration's own Phase 16 instruction ("only AFTER the Supabase implementation is working and verified: remove Firebase"), this is the correct state to be in at this checkpoint, not a shortfall — the "working and verified" bar has been met for the backend; the "switch" step (Phase 15) that would make removal safe has not yet begun.

## Test results

- Firebase side: unchanged from session start — `flutter analyze` 0 issues, `flutter test` 32/32, Firestore rules 211/211, 47-step chained scenario passing. Re-verified at the start of this session before any Supabase work began.
- Supabase side: 40/40 live scenario steps passing (`supabase/tests/rls_scenario_check.py`) against the real project, on the final run, after fixing two live-discovered bugs.

## Android / iOS results

Not re-run this session — no Flutter/Dart code changed, so there is nothing new to build or verify on either platform. Prior session's findings stand: Android structurally sound, blocked on a real `google-services.json`; iOS CocoaPods dependency resolution verified, full compile blocked on no local simulator runtime. Neither is affected by this session's backend-only work.

## Remaining blockers

1. **Google OAuth provider** must be configured in the Supabase dashboard by the project owner before Google Sign-In can be cut over (real credential, cannot be fabricated).
2. **The Flutter service-layer rewire** (35 files) has not started — see `docs/supabase-migration-status.md` for the exact, ordered plan for doing this safely, one feature at a time, with verification at each step.
3. **Real Supabase credentials** need to replace the placeholders in `lib/secrets.dart` before the app can talk to this project at all (the project ref, anon key, and URL are all now known and documented in this session's work, but were deliberately not written into `lib/secrets.dart` in this pass, since doing so with no Flutter code yet consuming them would be a config change with no corresponding tested behavior — exactly the "don't claim success without testing" principle this migration itself insists on).
4. **`pg_cron` availability** on this project's plan tier was not checked — needed before the `cleanupExpiredAnonMessages` equivalent can be scheduled.

## Remaining technical debt

- `clubs` has no DELETE policy (documented gap, `docs/supabase-schema.md`) — a product decision (cascade behavior on club deletion), not an oversight.
- The mission brief assumed a `reports` collection exists in the current product; it does not (the closest analogue is `moments.reports_count`). No fictitious table was built to match an assumption that didn't hold up against the reference implementation.
- `comments` RLS was designed by direct parity with the already-verified `post_likes` policies but wasn't independently exercised in the live scenario test — low risk given the parity, but not proven with the same rigor as the rest.

## Exact human actions required, in order

1. Configure the Google OAuth provider in the Supabase dashboard (Authentication → Providers → Google) with real client credentials, if Google Sign-In should be the cutover target — or decide email/password should go first instead, which needs no such step.
2. Review the schema/RLS/migration files (`supabase/migrations/*.sql`) and the security-model mapping before authorizing the Flutter cutover to begin.
3. Decide the `clubs` delete/cascade behavior (documented gap above) if club deletion should ever be supported.
4. When ready to begin Phase 15: say so explicitly, and expect it to proceed one feature at a time, each with its own real verification, not as a single large rewrite.

## Final status

**MIGRATION IN PROGRESS.**

Not INTERNAL TEST READY as a Supabase-backed app — the Flutter application does not run on Supabase yet; nothing about today's work changes what a real user experiences. It IS, however, a real, live, thoroughly-verified backend foundation: not a document, not an assumption, not "the schema looks right" — 40 real HTTP calls against a real database with real security policies, in the exact chained, adversarial shape (deny-direction assertions included) that has caught every serious bug this project has ever shipped. The honest, conservative call is that this session completed real infrastructure work and stopped at the correct, deliberate boundary before the higher-risk step of rewiring a working, already-hardened production application — not that it fell short of a larger claim.
