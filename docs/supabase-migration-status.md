# TrueKinn — Supabase Migration Status

**Last updated:** this session, immediately after live-verifying the RLS scenario test (40/40 passing).

## Done, and verified against the real live project (not a plan)

| Item | Evidence |
|---|---|
| Supabase project identified, unpaused, linked | `supabase link` succeeded; project confirmed `ACTIVE_HEALTHY` |
| Pre-existing unrelated schema found and handled | User confirmed disposable; dropped in its own migration, not silently folded into schema creation |
| Full schema (18 tables, matching all 18 Firestore collections) | `supabase/migrations/20260914000001_initial_schema.sql`, applied; confirmed via live `information_schema.tables` query |
| Full RLS policy set (every table) | `supabase/migrations/20260914000002_rls_policies.sql`, applied |
| RLS helper recursion bug found + fixed | `supabase/migrations/20260914000003_fix_rls_helper_recursion.sql` — found via live testing, not review |
| Counter-trigger RLS-blocking bug found + fixed | same migration |
| 40-step live scenario verification | `supabase/tests/rls_scenario_check.py`, run against real auth accounts + real JWTs + real PostgREST calls, 40/40 passing on the final run |
| College isolation (RLS-enforced, not just client-filtered) | scenario steps 2c, 3f, 4d, 5i, 6b, 7c, 8c — every one asserts the DENIED direction, not just the allowed one |
| Friendship-forgery prevention | scenario steps 3d (wrong order denied), 3e (correct order succeeds), 3g (duplicate denied by unique index) |
| Club admin self-escalation prevention | scenario step 5b |
| Chat sender-spoofing prevention | scenario step 4c |
| Two intentional bug-fixes-ahead-of-the-reference (Moments college scoping + report carve-out) | `supabase/migrations/20260914000002_rls_policies.sql`, documented in `docs/supabase-security-model.md` |

## Not done this session, and exactly why

**The Flutter application itself has not been touched.** `lib/` still runs entirely on Firebase; `pubspec.yaml` is unchanged; `flutter analyze`/`flutter test` were not re-run against app code because no app code changed. This is a deliberate stopping point, for three concrete reasons rather than running out of time mid-task:

1. **Scale.** 35 files import `firebase_auth`/`cloud_firestore` directly. Rewiring all of them to Supabase's client, in one pass, without individually re-verifying each feature the way this session verified the backend (real accounts, real chained sequences, both allow- and deny-directions), would risk exactly what the migration's own instructions warn against: claiming success without actually testing it, and breaking a currently-working, already-hardened app (32/32 tests, 211/211 rules tests, a verified live-on-device Android build) in the process.
2. **A real, external blocker for the primary sign-in method.** Google Sign-In — the app's actual primary auth method — cannot be cut over to Supabase Auth until the project owner configures a real Google OAuth client in the Supabase dashboard (see `docs/supabase-auth-migration.md`). Starting the Flutter auth rewiring before that exists would mean either building against a sign-in method the app doesn't actually use (email/password) or leaving the primary path broken mid-migration.
3. **The mission's own sequencing.** Phase 19 ("dual-backend safety") explicitly describes exactly this checkpoint as correct, not premature: "Firebase implementation → Supabase implementation → tests → verification → switch → remove old implementation," one feature at a time. This session completed "Supabase implementation → tests → verification" for the entire backend in one coherent pass (schema + RLS + live proof), which is substantially MORE than a plan — but "switch" (Phase 15, the Flutter service-layer rewire) and "remove old implementation" (Phase 16) are correctly sequenced as the next phase, not this one.

## Concretely, what Phase 15 (next session) should do, in order

1. Wait for (or work around, if the product wants an interim path) the Google OAuth provider being configured in the Supabase dashboard.
2. Replace `auth_gate.dart`'s Firebase-based bootstrap with a Supabase-Auth-based equivalent, feature-flagged or branch-isolated so it can be tested in place before replacing the Firebase path outright — mirroring this session's own `profiles_insert` policy and the live-verified bootstrap sequence (scenario steps 1a–1e).
3. One feature vertical at a time (feed → friends → chat → clubs → events → notifications → anon chat), each: build the Supabase-backed service, write a widget/integration test against it, verify manually, THEN remove the Firebase-backed equivalent for that feature — never both directions at once for the same feature.
4. Only after every feature is cut over: Phase 16 (remove `firebase_core`/`firebase_auth`/`cloud_firestore` from `pubspec.yaml`, delete `firestore.rules`/`functions/`, run the Phase 24 "search the whole repo for firebase" sweep this migration's own instructions specify).

## Unrelated security finding, disclosed during this session (not part of the migration itself)

While auditing this session's own new files for accidentally-committed secrets (a Phase 20 instruction), `supabase/functions/cleanup-moments/index.ts` was found to already exist in the repo — committed in the very first commit (`4b8f7bf`), already on `origin/main` — with a **real, live Supabase `service_role` key and project URL hardcoded directly in source** (for project ref `xzohkfdotsnzayiywrie`, a different, previously-unknown-to-this-migration Supabase project — not "ReServe dev"). The code as written didn't even function correctly (the secret was passed as a literal argument to `Deno.env.get()`, which looks up a variable by *name*, not by value).

This predates this session's work entirely and is unrelated to the migration. It was flagged to the user immediately upon discovery, in-conversation, with the explicit recommendation to rotate/revoke that key from that project's dashboard and to decide separately whether the repo's git history needs scrubbing (a disruptive, hard-to-reverse operation this session did not perform without being asked). The file itself was fixed in place — the hardcoded secret replaced with the correct `Deno.env.get("SUPABASE_URL")`/`Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` pattern (Edge Functions get both injected automatically at runtime; no explicit secret needed for these two) — closing the leak going forward, though not retroactively in git history.

Separately worth noting: this function's data model (`moments.media_path`, cleanup by `created_at < now() - 24h`) does not match the `moments` table this migration built (`media_url`, cleanup by an explicit `expires_at` field) — it appears to be a stale, disconnected scaffold from an earlier iteration of the product, not something this session integrated or relied on. Left as-is beyond the secret fix; not silently adapted to match the new schema, per this migration's own "don't invent/guess, document and stop" instruction.

## Live project state left behind

The "ReServe dev" project now contains the full TrueKinn schema + RLS, with the scenario test's data truncated back to empty (`profiles`/`posts`/etc. cleared) but the 3 synthetic test auth accounts (`a@nmit.ac.in`, `b@nmit.ac.in`, `c@rvce.edu.in`, password `TestPass123!`) left in place as known-good fixtures for whoever picks up Phase 15 next — deleting them seemed less useful than leaving a working, already-proven test harness in place. The unrelated `food_posts`/legacy `users` tables were dropped per the user's explicit confirmation (see `docs/supabase-migration-plan.md` Phase 1).

## Final status for this session

**MIGRATION IN PROGRESS.** Not INTERNAL TEST READY yet for Supabase specifically — the app doesn't run on it. The Firebase side remains at its own prior rating (INTERNAL TEST READY, per `docs/overnight-production-hardening-report.md`) and is unaffected by anything in this session — no Firebase code, rules, or Cloud Functions were modified.
