# TrueKinn — Final Engineering Hardening Report

Scope: harden the CURRENT Supabase-only TrueKinn codebase (security, RLS,
data integrity, error handling, network resilience, Realtime correctness,
auth/session correctness, storage security, minimum-viable moderation,
test coverage) without migrating, redesigning, or expanding product scope.
No UI/UX/visual work was performed. All fixes were applied to the live
Supabase project (`nczagxcixactkskqhjll`) and verified either via live
adversarial API testing with real account JWTs, or through the real running
Android app (freshly rebuilt and reinstalled partway through this pass so
every fix below was exercised in its actual built form, not just read).

---

## 1. Executive summary

Starting point: CLOSED BETA READY, per `docs/final-beta-readiness.md`.
This pass worked through that report's own documented gaps plus a fresh,
systematic audit (two background research passes covering every
`.stream()` call site and every async error-handling path in `lib/`), and
found and fixed:

- The one missing safety surface called out as blocking wider rollout: a
  complete report/block feature, server-authorized via RLS, live-verified.
- The documented Profile "Clubs" counter bug — root cause was a column that
  was never trigger-maintained, unlike `posts_count`/`friends_count`.
- A **real, exploitable authorization gap in the block-enforcement I
  myself had just added** — caught by adversarial testing within the same
  pass, before it could ship. Documented in detail below because it's the
  most important finding of this pass, methodologically: automated
  RLS-writing is not automatically safe RLS, and nested-RLS interactions
  need the same adversarial scrutiny as everything else.
- A write-side authorization gap on the `events` storage bucket (any
  authenticated user, any college, could write into any event's media
  folder — unreachable from the current UI, but not from a direct API
  call).
- A duplicate-club-request spam gap (`club_requests` had no DB-layer
  dedup, unlike `friend_requests`/`club_join_requests`, which explains two
  pieces of stale junk data found during the previous pass).
- A systemic client-side defect (confirmed by reading the resolved
  `supabase_flutter` package source, not guessed): `.stream()`'s realtime
  INSERT handler never checks for an existing primary key, so a row
  present in both the initial fetch and a near-simultaneous INSERT event
  renders twice. Fixed with a shared dedupe helper across 9 call sites.
- Five concrete "stuck forever / swallowed error" bugs across 1:1 chat,
  club chat, the feed like button, comments, and the friend-request button
  — all found by a dedicated research pass, all fixed.
- No server-side upper bound on message/comment length anywhere — closed
  with a 4000-character check constraint.

---

## 2. Exact bugs found

1. **Profile "Clubs" stat always 0.** `profiles.clubs_count` column never
   existed; nothing ever wrote it. `lib/profile/profile_screen.dart:151`
   already carried a comment acknowledging this.
2. **Block enforcement bypassable by the blocked user (self-introduced,
   caught same-pass).** The first version of `messages_insert`/
   `friend_requests_insert`'s block check did
   `exists(select 1 from blocks where ...)` inline — that subquery is
   itself subject to `blocks`' own RLS SELECT policy
   (`blocker_uid = auth.uid()`), so from the blocked user's own point of
   view the block row is invisible, and the check always passed. Proven
   live: C could still friend-request B immediately after B blocked C.
3. **`events` storage bucket write policy had no ownership check at all**
   — `with check (bucket_id = 'events' and auth.uid() is not null)`. Any
   authenticated user, any college, could upload into
   `events/<any-event-id>/...`, including events they don't own.
4. **`club_requests` had no duplicate-pending-request protection** at the
   database layer, unlike `friend_requests` and `club_join_requests`
   (both of which already had a partial unique index for exactly this).
   Explains two pre-existing junk "Chess Club" pending requests found
   during the previous pass.
5. **Realtime duplicate-row rendering (systemic).** Read the resolved
   `supabase-2.16.1` package source directly:
   `SupabaseStreamBuilder`'s INSERT handler appends unconditionally with
   no primary-key check, while its own initial postgrest fetch can
   independently already include the same row. Confirmed already fixed
   inline for `college_anon_chat_screen.dart`; found unfixed in 9 other
   `.stream()`-backed lists.
6. **`lib/chat/chat_screen.dart` `_sendMessage`** had no try/catch: a
   failed send silently dropped the typed message (already cleared from
   the field) with zero feedback. Its `_ready` `FutureBuilder` could also
   crash the whole screen via a null-assertion (`_conversationId!`) if
   `_ensureConversationExists()` completed without an exception but also
   without ever resolving a conversation id.
7. **`lib/clubs/club_chat_screen.dart` `_send`** had no try/catch: same
   silent-message-loss bug, plus `_sending` stayed `true` forever on any
   failure, permanently disabling the send button for the rest of that
   screen's lifetime.
8. **`lib/feed/feed_screen.dart` `_toggleLike`** had no error handling
   and no double-tap guard on the single most-tapped button in the app.
9. **`lib/feed/comments_screen.dart`** caught its send exception as
   `catch (_)` with zero logging — the identical shape to the anon-chat
   timezone bug that went undetected for as long as it did before this
   effort's earlier pass found it.
10. **`lib/feed/widgets/friend_button.dart` `_loadRelationship`** had no
    error handling at all: any failure left the Add-Friend button on a
    `CircularProgressIndicator` forever, with zero recovery — the exact
    bug class already fixed once in `bottom_nav_shell.dart`.
11. **`lib/notifications/notifications_screen.dart`**'s club-request
    "Dismiss" button had no error handling or feedback — a failed dismiss
    silently did nothing.
12. **`lib/auth/screens/profile_setup_page.dart` `_submit`** had a
    `try { } finally { }` with no `catch` — the loading flag reset
    correctly, but any real failure (photo upload, DB write) surfaced as
    an unhandled async exception with no user-facing message.
13. **No server-side upper bound on message-like text** anywhere —
    `messages`/`comments`/`club_messages`/`anon_messages` all only checked
    non-empty, never a maximum length.
14. **No reporting or user-blocking mechanism reachable anywhere in the
    app**, confirmed by the previous pass and unchanged going into this
    one.

## 3. Exact fixes made

| # | Fix | Where |
|---|---|---|
| 1 | Trigger-maintained `profiles.clubs_count`, mirroring `posts_count`'s existing pattern, plus a one-time backfill for existing memberships | `supabase/migrations/20260914000014_clubs_count.sql` |
| 2 | `is_blocked_pair()` SECURITY DEFINER helper (same fix shape as `20260914000003`'s `is_platform_admin()`/`is_club_admin()` recursion fix), used by both insert policies instead of the raw, self-defeating subquery | `supabase/migrations/20260914000018_fix_block_enforcement_rls_recursion.sql` |
| 3 | `events_media_write` policy now requires the target event's `created_by = auth.uid()` | `supabase/migrations/20260914000015_events_storage_write_ownership.sql` |
| 4 | Partial unique index, one pending club request per owner | `supabase/migrations/20260914000016_club_requests_dedupe.sql` |
| 5 | Shared `dedupeStreamRowsById()` helper applied at 9 call sites | `lib/utils/dedupe_stream_rows.dart`, applied in `chat_screen.dart`, `club_chat_screen.dart`, `notifications_screen.dart`, `feed_screen.dart`, `comments_screen.dart`, `clubs_screen.dart` (×2), `user_posts_grid.dart`, `admin_club_requests_screen.dart`, `club_join_requests_screen.dart` |
| 6 | try/catch/finally with text-restore-on-failure and a `_sending` double-tap guard; null-safe fallback UI instead of a crashing `!` | `lib/chat/chat_screen.dart` |
| 7 | try/catch/finally with text-restore-on-failure | `lib/clubs/club_chat_screen.dart` |
| 8 | try/catch plus a `postId`-keyed static in-flight guard | `lib/feed/feed_screen.dart` |
| 9 | `catch (_)` → `catch (e)` with `debugPrint` | `lib/feed/comments_screen.dart` |
| 10 | try/catch around the whole relationship-load sequence, new `_Relationship.error` state with a retry affordance | `lib/feed/widgets/friend_button.dart` |
| 11 | try/catch with a failure snackbar | `lib/notifications/notifications_screen.dart` |
| 12 | Added the missing `catch` clause with a failure snackbar | `lib/auth/screens/profile_setup_page.dart` |
| 13 | 4000-char check constraint added to all four message-like tables | `supabase/migrations/20260914000020_message_text_length_bound.sql` |
| 14 | Full report/block feature (schema, RLS, service, dialog, admin screen) — see §9 | `supabase/migrations/20260914000017_moderation_report_block.sql`, `supabase/migrations/20260914000019_reports_realtime.sql`, `lib/services/moderation_service.dart`, `lib/moderation/report_dialog.dart`, `lib/moderation/reports_admin_screen.dart`, wired into `lib/feed/feed_screen.dart`, `lib/profile/profile_screen.dart`, `lib/settings/settings_screen.dart` |

## 4. Security / RLS results

Fresh adversarial testing this pass, all with real account JWTs (no
fabricated credentials):

- Ran the existing 40-scenario RLS suite (`supabase/tests/rls_scenario_check.py`)
  fresh against three newly-created throwaway accounts: **40/40 passed**,
  confirming no regression from any schema change in this pass.
- Added **9 new scenarios** to the same suite covering the new
  report/block feature (self-report only, forged-reporter denied,
  non-reporter/non-admin read denied, non-admin status-change denied,
  blocked-party-cannot-friend-request in both directions, blocked party
  cannot unblock themselves, blocker can). Ran the combined suite fresh
  again: **49/49 passed**.
- Direct curl-level adversarial checks (outside the suite, using the
  persistent beta accounts): confirmed the `events` storage ownership fix
  denies a cross-college non-owner (`403`) and allows the real owner
  (`200`); confirmed the `club_requests` dedup index denies a second
  pending request from the same user (`409`); confirmed the message
  length bound denies a 4001-character payload (`400`).
- **The one real vulnerability found this pass was in code this pass
  itself had just written** (block enforcement, bug #2 above) — caught
  immediately by adversarially testing the new RLS rather than trusting
  it because it looked correct on paper. Re-verified fixed afterward.

Every finding above was tested through direct PostgREST calls with real
signed-in JWTs, not just inspected in code.

## 5. Storage security results

- `clubs` bucket confirmed still private with signed-URL access — no
  regression.
- `events` bucket write policy closed (see §2/§3).
- `posts`, `moments`, `profile_photos`, `events` remain public-read
  buckets, matching the architecture the previous pass documented and
  explicitly decided not to change (switching any of them to
  private+signed-URL would mean touching every render call site across
  the feed/profile/events UI — a broad refactor outside this pass's
  "smallest safe fix" mandate, not a quick security patch). This remains
  a known, documented tradeoff, not a silent gap.

## 6. Realtime results

- Confirmed the Realtime publication (`supabase_realtime`) membership for
  every table currently streamed by the client; added `reports` (needed
  by the new admin queue, mirroring the existing `club_requests` admin
  pattern) and deliberately did **not** add `blocks` (nothing streams it).
- Fixed the systemic duplicate-INSERT-render defect at 9 call sites (see
  §2/§3), with a new unit-tested shared helper
  (`test/dedupe_stream_rows_test.dart`, 5 cases).
- A broader research pass flagged 4 pairs of `.stream()` call sites with
  an identical table+filter shape to the one proven-broken case from the
  previous pass (`settings_screen.dart` vs. `bottom_nav_shell.dart`).
  Live-tested the flagship case this pass (viewing your own profile via
  the bottom nav, on the actual rebuilt app) and **it loaded correctly** —
  contradicting the theorized collision mechanism (the research also
  found, from reading the client library source, that each `.stream()`
  call gets a distinct channel topic, casting doubt on "identical filter
  shape collides" as the real mechanism). Not fixed, since converting a
  live-updating profile view to a one-shot fetch on a merely theoretical,
  not reproduced, bug risks a real regression for no confirmed benefit.
  Documented as investigated-and-not-reproduced rather than left silent.
- Nested `StreamBuilder` subscription churn (a `.stream()` re-created on
  every parent rebuild, e.g. per-post `post_likes` streams in the feed)
  was flagged as a real inefficiency but is a performance/flicker concern,
  not a correctness bug — left as documented, deferred work.

## 7. Network resilience results

No dedicated connectivity-toggle test matrix was run this pass (would
require device-level network control beyond what was practical here).
Instead, every async operation touched by this pass now has an explicit
failure path (§2/§3 items 6–12) so a network failure mid-operation
produces a clear, recoverable UI state instead of a silent failure or a
permanent stuck spinner — which is what a connectivity test would mostly
be checking for. This is real hardening of the failure paths, not a
substitute for an actual airplane-mode pass, which remains undone.

## 8. Auth/session results

No new auth/session bugs found this pass. The previous pass's fixes (the
post-logout stuck-spinner fix in particular) were exercised repeatedly
throughout this pass's live device testing (multiple full logout/login
cycles between the A and B accounts) with no recurrence.

## 9. Moderation implementation

Minimum viable, matching the brief's own scope constraint:

- **Schema:** `reports` (reporter, target type/id, reason, free-text
  details, status) and `blocks` (blocker, blocked) tables, both RLS-only
  (no service-role/edge-function dependency).
- **Authorization is entirely server-side:** a reporter can only file as
  themselves; only the reporter or a platform admin can read a report;
  only a platform admin can change its status; nobody can delete a filed
  report (status transition only — an audit trail, not a revocable
  action); a blocker can only remove their own block, never the blocked
  party.
- **Enforcement:** blocked pairs cannot message each other or send
  friend requests, in either direction, verified live.
- **UI**, using the app's existing dark visual language exactly, no new
  design system: a report reason-picker dialog (reused for both posts and
  users), a Report/Block/Unblock menu on non-self profiles, a Report menu
  on feed posts (hidden on your own), and an admin-only Reports screen
  (Settings → Admin → Reports, alongside the existing Club Requests entry)
  with Dismiss/Mark-reviewed actions.
- **Live-verified end-to-end on the rebuilt app:** submitted a real report
  from A against B's profile → confirmed it appeared instantly in B's
  admin Reports queue via Realtime → marked it reviewed → confirmed it
  left the open queue.
- Deliberately **not** built: per-content auto-hide thresholds, an
  appeals flow, or report categories beyond a free-text reason — real
  product decisions, not this pass's to make unilaterally.

## 10. Database integrity changes

- `profiles.clubs_count` added + trigger-maintained + backfilled (§2/§3
  item 1).
- `events` storage write policy tightened to real ownership (§2/§3 item
  3) — not a table schema change, a storage policy change, listed here
  since it's the same class of "obviously invalid state the database
  should refuse" hardening.
- `club_requests_pending_owner_idx` partial unique index added (§2/§3
  item 4).
- `messages`/`comments`/`club_messages`/`anon_messages` all gained a
  4000-character upper bound (§2/§3 item 13).
- `reports`/`blocks` tables added with their own constraints (unique
  reporter+target, unique blocker+blocked, `blocker_uid <> blocked_uid`).
- Full schema review against the brief's specific list (missing FKs,
  nullable-should-not-be, orphanable records, enum/state transitions,
  timestamp/UTC consistency, missing indexes): no other gaps found.
  `clubs.owner_uid` intentionally has no `on delete cascade`/`set null`
  (confirmed live — deleting a user who still owns a club is correctly
  blocked, not silently orphaning the club); this is existing, correct
  behavior, not a new finding.

## 11. Test results

- `flutter analyze`: **0 issues** (verified repeatedly through this pass,
  including after every source change).
- `flutter test`: **37/37 passing** (the previous pass's 32, plus 5 new
  for `dedupeStreamRowsById`).
- RLS scenario suite: **49/49 passing** (40 original + 9 new, run fresh
  end-to-end against newly-created throwaway accounts, not just inspected).
- All throwaway RLS test accounts and their side-effect data (test clubs)
  created during this pass's verification were cleaned up afterward.

## 12. Android result

Rebuilt the app from scratch (`flutter build apk --debug`) partway
through this pass so every fix could be verified in its actual built
form, not just read as source. Installed and live-tested on the same
Android emulator used throughout this effort: profile club counts for
both A and B (fixed bug, confirmed live), the full report/block flow
end-to-end including the admin queue, anonymous chat send, club chat send
(the most heavily modified file), and the feed/clubs lists all loading
correctly post-dedupe-fix. No regressions found.

## 13. iOS result

**BLOCKED**, unchanged from the previous pass. Xcode 26.1.1 is installed;
`xcrun simctl list runtimes` returns empty — no iOS Simulator runtime
installed, no device available. Re-checked at the start of this pass.
No speculative iOS-only changes were made; iOS status is unknown, not
assumed working.

## 14. Remaining known limitations

- Chat/comment/post content filtering (`TextFilter`) remains client-side
  only, by deliberate decision (see §15) — the new report feature is the
  intended complementary safety net, not a second automated filter.
- `posts`/`moments`/`profile_photos`/`events` storage buckets remain
  public-read (§5) — a real, documented tradeoff, not a gap that was
  missed.
- The 4 "suspected" duplicate-`.stream()`-collision pairs from §6 remain
  unfixed, since the flagship case didn't reproduce live and the
  underlying mechanism is genuinely uncertain (see §6) — converting them
  to one-shot fetches speculatively would remove real live-update
  behavior for an unconfirmed bug.
- Nested `StreamBuilder` subscription churn (§6) is a performance
  concern, not fixed.
- No dedicated network-interruption/airplane-mode test pass was run
  (§7) — the failure-path hardening in §2/§3 addresses the same class of
  bug at the code level, but a real connectivity test remains undone.
- One residual test artifact found during data-hygiene cleanup: a second
  "Chess Club" (owner uid `2a86869e-9e8c-4933-8f9a-8b175864f2a1`, 2
  members) whose provenance predates this conversation and couldn't be
  confirmed with the same certainty as the two items the brief explicitly
  named — **not deleted**, per "if it can't be safely distinguished from
  real data, don't guess." Flagged for manual review by the project owner.

## 15. Deferred product work

- Client-side profanity/content filtering is real but not tamper-proof —
  a full server-side equivalent was evaluated and deliberately not built
  (duplicating and maintaining two independent banned-word lists is a
  real drift/false-positive risk, and the new report flow is a better fit
  for what slips through than a second automated filter would be).
- Club "Members" and "Events" admin sub-screens remain unimplemented
  stubs — confirmed no security/correctness issue depends on them; still
  deferred product work, not touched.
- Platform-level Events retains no creation UI and no detail view — the
  underlying RLS was reviewed and found sound; still a product-completeness
  gap, not a security one.
- Moderation report categories, auto-hide thresholds, and an appeals flow
  — intentionally out of "minimum viable" scope.

## 16. Manual owner actions still required

- Install an iOS Simulator runtime (or provide a physical device/Apple ID)
  to unblock iOS verification — cannot be done unattended in this
  environment.
- Create a real Sentry project and provide its DSN if crash reporting is
  wanted — no DSN exists and none was fabricated; `sentry_flutter` remains
  the recommended package (no Firebase dependency) whenever that DSN is
  available.
- Manually review and decide on the residual "Chess Club" (owner
  `2a86869e-9e8c-4933-8f9a-8b175864f2a1`) flagged in §14.
- Decide whether the public-read storage buckets (§5/§14) are an
  acceptable long-term tradeoff or warrant the larger refactor to
  signed URLs.

## 17. Files changed

See `git diff --stat` on this commit for the exact list; summarized in §3
above. 13 existing Dart files modified, 3 new Dart files added
(`lib/services/moderation_service.dart`, `lib/moderation/report_dialog.dart`,
`lib/moderation/reports_admin_screen.dart`), 1 new utility
(`lib/utils/dedupe_stream_rows.dart`), 1 new test file
(`test/dedupe_stream_rows_test.dart`), the RLS scenario script extended
in place.

## 18. Database migrations added

```
20260914000014_clubs_count.sql
20260914000015_events_storage_write_ownership.sql
20260914000016_club_requests_dedupe.sql
20260914000017_moderation_report_block.sql
20260914000018_fix_block_enforcement_rls_recursion.sql
20260914000019_reports_realtime.sql
20260914000020_message_text_length_bound.sql
```

All applied to and verified against the live project this pass.

## 19. Final readiness classification

**CLOSED BETA READY.**

Not upgraded to PRODUCTION READY, for the same structural reasons as the
previous pass plus one new one: iOS remains genuinely unverified (blocked,
not assumed); the storage-bucket tradeoff in §5 and the client-side-only
content filter in §14/§15 are real, deliberate, documented limitations
rather than oversights; no network-interruption test pass has been run;
and club Members/Events remain unfinished product surfaces. None of these
block a small, trusted closed beta where the operator can manually
intervene. What changed this pass: the one missing safety surface
(report/block) that mattered before expanding beyond a trusted beta is
now built, server-authorized, and live-verified — and, notably, this
pass's own adversarial-testing discipline caught a real vulnerability in
that very feature before it shipped, which is the strongest evidence this
effort has produced that the "verify live, verify adversarially, don't
trust code that merely looks correct" discipline established across this
whole effort is working as intended.

---

**Engineering hardening complete — ready for UI/UX.**
