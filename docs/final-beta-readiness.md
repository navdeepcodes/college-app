# TrueKinn — Final Beta Readiness Report

> **Update (2026-09-14, engineering hardening pass):** a follow-on hardening
> pass closed the moderation gap this report originally documented, fixed
> the Profile "Clubs" counter bug, and found/fixed several other concrete
> bugs (duplicate Realtime rendering, five stuck-spinner/swallowed-error
> paths, a storage authorization gap, a missing DB-layer dedup on club
> requests, and a self-caught RLS gap in the new moderation feature's own
> first draft). Full detail in `docs/final-engineering-hardening-report.md`.
> The rows below are updated in place to reflect the current state; the
> narrative sections at the bottom still describe this report's own
> original pass and are kept for history.

Generated from a live, on-device, real-user validation pass on the actual running
Flutter app (Android emulator) against the live Supabase project
(`nczagxcixactkskqhjll`), using three synthetic accounts:

- **User A** — `beta-a@nmit.ac.in` (NMIT)
- **User B** — `beta-b@nmit.ac.in` (NMIT, made platform admin for this pass)
- **User C** — `beta-c@rvce.edu.in` (RVCE — different college, for isolation checks)

Password for all: `BetaTest2026!`. No fabricated credentials were used anywhere;
where a real credential was required and unavailable (Google OAuth client
config, a Sentry DSN), the corresponding feature was documented as blocked
rather than faked.

This report is deliberately conservative: a row is only marked PASS if it was
either exercised through the real running app this pass, or through the real
running app in the immediately preceding session of this same effort (noted
per-row). Rows not re-verified this pass are marked accordingly rather than
assumed to still work.

---

## Status matrix

| Area | Implemented | Actually Tested | Result | Remaining issue |
|---|---|---|---|---|
| **AUTH** | Yes | Yes (live) | PASS | Google OAuth untestable (dashboard OAuth client not configured — not fabricated). Email/password signup, login, logout, session restore, profile setup, invalid credentials all verified live. Two real bugs found and fixed this effort: permanently-stuck post-logout spinner (most severe bug found), and college dropdown missing RVCE/BMS/PES. |
| **FEED** | Yes | Partially (prior session) + hardening pass | PASS | Post create/like/comment/empty-state covered in the session immediately preceding this one. Hardening pass fixed a real bug: the like button had no error handling and no double-tap guard; also added a Report action to post headers. The inappropriate placeholder test post ("Live TestUser") flagged in the original version of this row has been **deleted**, along with its storage image. |
| **FRIENDS** | Yes | Yes (live) | PASS | Send → notify → accept → counts-update flow fully verified live. Found and fixed a real bug: friend-request **accept was completely non-functional** through the real app (FK constraint blocked the delete step) despite passing RLS scenario tests — the scenario test exercised a different (UPDATE-based) code path than the real client. Fixed via migration + regression-verified. A second bug (accept success left the UI spinner stuck forever) also found and fixed. Reject and cross-college request were **not** independently re-driven through the UI this pass; only send/accept/duplicate-tap were. |
| **CHAT (1:1)** | Yes | Yes (prior session) | PASS | Send/receive/reply/reopen verified live in the session immediately preceding this one. |
| **ANONYMOUS CHAT** | Yes | Yes (live) | PASS | Found and fixed a **critical, universally-reproducible bug**: every real user in India (the app's actual target market — NMIT/RVCE/BMS/PES are all Bangalore colleges) could not send an anonymous message at all, because the client computed `expires_at` from local time without `.toUtc()`, and the server-side RLS time-window check silently rejected every insert. Fixed. Also fixed a UI-only duplicate-message-render bug (dedup by id). Cross-user live delivery and User C's cross-college denial were relied on from prior RLS scenario coverage rather than re-driven live this pass (90-second message TTL made live multi-account switching impractical). |
| **CLUBS** | Yes | Yes (live, full flow) | PASS | Full flow driven live this pass: A creates a club with description/phone/USN + real photo ID-card upload → submits → B (platform admin) opens Settings → Club Requests → sees the real pending request rendered via the new **signed-URL** ID-card preview (first live test of that mechanism — previously only curl-verified) → approves → club auto-bootstraps A as club admin → club appears correctly in Explore with the right member count → B requests to join → A (club owner) approves via the Club Admin dashboard → member count updates to 2 for both accounts. **Sub-features found unimplemented (stubs, not bugs, reviewed again in the hardening pass — no security/correctness issue depends on them):** "Members" and club-level "Events". **Profile-stats bug: FIXED in the hardening pass.** `profiles.clubs_count` was never trigger-maintained (unlike `posts_count`/`friends_count`); added the missing trigger + a backfill migration, live-verified on the rebuilt app for both A and B showing the correct count. |
| **CLUB CHAT** | Yes | Yes (live) | PASS | Explicitly flagged by the original brief as "previously a total outage in the Firebase version" — verified this is **no longer the case**. Opened live by both the club owner (A) and a regular member (B); A sent a message, B received and saw it correctly left-aligned as A's message; B replied, A received it. Real, working, bidirectional. |
| **EVENTS** | Partially | Yes (live) | PARTIAL | A platform-level, read-only Events list exists (reachable via the calendar icon in the Feed app bar) and correctly displays pre-existing events. However: (1) tapping an event does nothing — no detail screen exists; (2) there is no event-creation UI anywhere in the app, at either the platform level or the club-admin level (the club admin dashboard's "Events" entry is an explicit "coming next" stub). Per the brief's own instruction ("if creation is not currently exposed, document why"): it is not exposed because it has not been built yet, not because of a bug. |
| **NOTIFICATIONS** | Yes | Yes (live) | PASS | Friend-request notifications verified live (and its stuck-spinner bug fixed, see FRIENDS). Club-request admin notification verified live this pass: submitting a club request as A correctly produced a "New Club Request — Chess Club Test wants to join TrueKinn" notification for admin B, with working Review/Dismiss actions and correct Realtime delivery. |
| **MOMENTS** | Disabled (by design) | N/A | N/A — untouched | `kMomentsEnabled = false` preserved exactly as instructed. Not enabled, not redesigned, not removed, camera/video_player dependencies untouched. One defensive `.toUtc()` consistency fix was applied to `moment_camera_screen.dart` (the same timezone bug class found live in anonymous chat) but is explicitly **not** claimed as live-verified, since the screen is unreachable while the feature is disabled. |
| **MODERATION / REPORTING** | Yes (as of hardening pass) | Yes (live, end-to-end) | PASS | **Built and live-verified in the hardening pass.** Report (post/user) + block/unblock, both fully RLS-authorized: a reporter can only file as themselves, only the reporter/a platform admin can read a report, only an admin can change its status, nobody can delete one; blocked pairs cannot message or friend-request each other in either direction; a blocked user cannot unblock themselves. Live-verified: A reported B's profile → the report appeared instantly in B's new admin Reports queue → marked reviewed → left the open queue. A real vulnerability in the block-enforcement's first draft (nested-RLS made the check invisible from the blocked user's own point of view) was found and fixed via a SECURITY DEFINER helper *within this same pass*, before it shipped — see the hardening report for detail. Chat content filtering (`TextFilter`) remains client-side only by deliberate decision (documented, not a gap that was missed) — the new report flow is the intended complementary safety net. Server now also refuses obviously-invalid message states it didn't before (4000-char upper bound added to all message-like tables). |
| **STORAGE SECURITY** | Yes | Yes (live + adversarial) | PASS | The `clubs` bucket privacy hole (public-read exposure of ID-card photos via `getPublicUrl()`) called out explicitly in the brief has been **fully closed**: bucket flipped to `public = false`, `id_card_url` now stores a private object path (not a public URL), and the admin review screen resolves it via a 5-minute `createSignedUrl()`. Verified adversarially via curl (uploader read 200, non-admin/non-uploader read 400, old public-URL-style path 400) *and* now verified live end-to-end through the real admin UI. **Hardening pass:** full bucket-by-bucket audit found and closed a real gap — the `events` bucket's write policy had no ownership check at all (any authenticated user, any college, could write into any event's media folder); now requires `created_by = auth.uid()` on the target event, adversarially verified (cross-college denied 403, owner allowed 200). `posts`/`moments`/`profile_photos`/`events` remain public-read by deliberate, documented decision (switching them to signed URLs would mean refactoring every render call site across the feed/profile/events UI). |
| **RLS / SECURITY** | Yes | Yes (live, adversarial, this pass) | PASS | All club-related adversarial checks from the original pass (4/4) still hold. **Hardening pass:** the actual checked-in 40-scenario suite (`supabase/tests/rls_scenario_check.py`) was run fresh end-to-end against new throwaway accounts — **40/40 passed** — then extended with 9 new scenarios covering the new moderation feature and run again — **49/49 passed**. Also found and fixed a real vulnerability in the moderation feature's own first-draft RLS (block enforcement was invisible from the blocked user's own point of view due to nested-RLS on the `blocks` table itself) — caught by adversarial testing within the same pass, before it shipped, and fixed via a SECURITY DEFINER helper mirroring the existing `is_platform_admin()` pattern. Also closed a duplicate-club-request DB-layer gap (`club_requests` had no dedup index, unlike `friend_requests`/`club_join_requests`). |
| **REALTIME** | Yes | Yes (live) | PASS (with fixed regressions) | Original pass: two duplicate-`.stream()`-subscription bugs fixed (Settings' Anonymous ID; anonymous chat's duplicate message render). **Hardening pass:** confirmed via the resolved client library's own source that `.stream()`'s realtime-INSERT handler never checks for an existing primary key — a systemic defect, not folklore — and fixed it at the 9 other call sites that lacked the dedupe-by-id step anon chat already had, with a new shared, unit-tested helper. The suspected `profile_screen.dart`/`bottom_nav_shell.dart` collision (and 3 similarly-shaped pairs found by a fresh audit) was live-tested on the rebuilt app this pass — **it loaded correctly**, not reproduced, so left untouched rather than "fixed" speculatively. |
| **ERROR HANDLING / NETWORK** | Partially tested | Partially (incidental) + hardening pass | PARTIAL | No dedicated network-interruption/backgrounding pass has been run at any point in this effort. **Hardening pass** found and fixed five concrete stuck-spinner/swallowed-error bugs via a dedicated research pass: 1:1 chat send (silent message loss + a possible screen crash via a null-assertion), club chat send (send button could get stuck disabled forever), the feed like button (no error handling, no double-tap guard), comments send (exception swallowed with zero logging), and the friend-request button (permanent stuck spinner on any failure, same bug class as the original pass's `bottom_nav_shell.dart` fix). All fixed with proper try/catch/finally and, where applicable, a retry affordance. A real connectivity/airplane-mode test pass is still undone. |
| **ANDROID** | Yes | Yes (live) | PASS | Original pass plus a full app rebuild (`flutter build apk --debug`) partway through the hardening pass, reinstalled and re-tested live so every fix above was verified in its actual built form. `flutter analyze`: 0 issues. `flutter test`: 37/37 passing (32 original + 5 new for the dedupe helper). |
| **IOS** | Unknown | **No — blocked** | BLOCKED | Xcode 26.1.1 is installed, but **no iOS Simulator runtime is installed** (`xcrun simctl list runtimes` returns empty) and no simulator device exists. Installing a runtime requires an interactive download (and typically an Apple ID) that could not be performed unattended in this environment. No speculative iOS-only changes were made. iOS readiness is genuinely unknown, not assumed. |

---

## Notable fixes made this effort (see git log for full detail)

1. `clubs` storage bucket flipped private + signed-URL admin review flow (closes the explicit ID-card public-exposure issue).
2. Duplicate-`.stream()` collision bugs fixed in Settings (Anonymous ID) and Anonymous Chat (message dedup).
3. Permanently-stuck post-logout loading spinner fixed via `pushAndRemoveUntil` with a fresh `AuthGate` — the single most severe bug found this effort.
4. College dropdown extended to cover RVCE/BMS/PES (was NMIT-only, silently mis-recording other colleges' display name — `college_id` itself was always correct).
5. Friend-request accept was **completely broken** through the real app (FK constraint) — fixed via `ON DELETE SET NULL` migration; its own follow-on stuck-spinner bug also fixed.
6. Anonymous chat send was **completely broken for every real user in India** (missing `.toUtc()` against a server-side RLS time-window check) — fixed. This is arguably the most impactful fix of the whole effort given the app's actual target market.

## Notable gaps found and *documented*, not fixed (as of the hardening pass)

- Chat content filtering is confirmed client-side-only (deliberate — see the MODERATION row).
- Club "Members" and "Events" admin sub-screens are stubs — reviewed again, no security issue depends on them.
- Platform Events has no creation UI and no detail view.
- `posts`/`moments`/`profile_photos`/`events` storage buckets remain public-read (deliberate tradeoff, documented in the STORAGE SECURITY row).
- 4 suspected duplicate-`.stream()`-collision pairs (same shape as a previously-proven bug) investigated, not reproduced live, left untouched.
- Nested `StreamBuilder` subscription churn (a stream re-created on every parent rebuild) — a performance/flicker concern, not a correctness bug.
- One residual test artifact ("Chess Club", owner uid `2a86869e-...`, provenance predates this conversation) flagged for manual owner review rather than guessed at and deleted.
- iOS build/run status is unknown (environment blocker, documented above).
- Crash reporting: evaluated again, still no DSN available; not fabricated.
- Push notifications: still explicitly out of scope; not implemented.

**Superseded by the hardening pass** (see `docs/final-engineering-hardening-report.md` for full detail): no moderation/reporting feature → now built; Profile "Clubs" stat bug → fixed; the two junk `club_requests` rows and the inappropriate placeholder feed post → deleted; the `profile_screen.dart` duplicate-stream risk → live-tested, not reproduced.

## Final automated verification (as of the hardening pass)

- `flutter analyze` — **no issues found**.
- `flutter test` — **37/37 passing** (32 original + 5 new for the Realtime-dedupe helper).
- RLS scenario suite (`supabase/tests/rls_scenario_check.py`) — **49/49 passing**, run fresh end-to-end (40 original scenarios + 9 new moderation scenarios).
- Live adversarial RLS/storage checks (club escalation, block enforcement, events storage ownership, club-request dedup, message length bound) — **all denied/enforced as expected**.
- Android build/install/runtime — app rebuilt from scratch, reinstalled, and re-verified live on the emulator.
- iOS build — **not run** (blocked, see IOS row).

## Readiness classification

**CLOSED BETA READY.**

Reasoning: every major user-facing flow has now been genuinely exercised
through the real running app across two passes, and every bug actually found
through that process — including several that would have been silent,
100%-reproducible dealbreakers, and one real vulnerability caught in the
moderation feature's own first draft by adversarially testing it rather than
trusting it on sight — has been fixed and re-verified live. The one missing
safety surface (moderation) that mattered before widening beyond a trusted
beta is now built and server-authorized.

It is **not** classified PRODUCTION READY because: iOS status is completely
unknown (not merely untested — unbuildable in this environment); a few
non-critical UI sub-features (club Members/Events, platform Events detail)
are unfinished stubs; several storage buckets remain public-read by deliberate
tradeoff rather than full signed-URL coverage; chat content filtering remains
client-side only; and no dedicated network-resilience/backgrounding test pass
has been run. None of these block a small, trusted closed beta where the
operator can manually intervene, but they should be resolved before opening
the app to the general public. Full detail on this pass's work:
`docs/final-engineering-hardening-report.md`.
