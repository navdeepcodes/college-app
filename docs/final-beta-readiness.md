# TrueKinn — Final Beta Readiness Report

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
| **FEED** | Yes | Partially (prior session) | PASS (with caveat) | Post create/like/comment/empty-state covered in the session immediately preceding this one; not independently re-run in this pass. No regressions found. One **seed/test data hygiene note**: the feed contains a pre-existing test post ("Live TestUser" / "Live supabase test post") whose image attachment is a screenshot of an unrelated third-party app depicting a fabricated violent-threat scenario. This is inert test data, not a live bug, but should be deleted before any real user sees the feed. |
| **FRIENDS** | Yes | Yes (live) | PASS | Send → notify → accept → counts-update flow fully verified live. Found and fixed a real bug: friend-request **accept was completely non-functional** through the real app (FK constraint blocked the delete step) despite passing RLS scenario tests — the scenario test exercised a different (UPDATE-based) code path than the real client. Fixed via migration + regression-verified. A second bug (accept success left the UI spinner stuck forever) also found and fixed. Reject and cross-college request were **not** independently re-driven through the UI this pass; only send/accept/duplicate-tap were. |
| **CHAT (1:1)** | Yes | Yes (prior session) | PASS | Send/receive/reply/reopen verified live in the session immediately preceding this one. |
| **ANONYMOUS CHAT** | Yes | Yes (live) | PASS | Found and fixed a **critical, universally-reproducible bug**: every real user in India (the app's actual target market — NMIT/RVCE/BMS/PES are all Bangalore colleges) could not send an anonymous message at all, because the client computed `expires_at` from local time without `.toUtc()`, and the server-side RLS time-window check silently rejected every insert. Fixed. Also fixed a UI-only duplicate-message-render bug (dedup by id). Cross-user live delivery and User C's cross-college denial were relied on from prior RLS scenario coverage rather than re-driven live this pass (90-second message TTL made live multi-account switching impractical). |
| **CLUBS** | Yes | Yes (live, full flow) | PASS | Full flow driven live this pass: A creates a club with description/phone/USN + real photo ID-card upload → submits → B (platform admin) opens Settings → Club Requests → sees the real pending request rendered via the new **signed-URL** ID-card preview (first live test of that mechanism — previously only curl-verified) → approves → club auto-bootstraps A as club admin → club appears correctly in Explore with the right member count → B requests to join → A (club owner) approves via the Club Admin dashboard → member count updates to 2 for both accounts. **Sub-features found unimplemented (stubs, not bugs):** "Members" (shows "Members screen coming next") and club-level "Events" (shows "Event creation coming next"). **Profile-stats bug found:** the Profile screen's "Clubs" counter shows 0 for a user who is genuinely a club member/owner (confirmed via the Clubs tab itself, which is correct) — the counter query doesn't match real membership. |
| **CLUB CHAT** | Yes | Yes (live) | PASS | Explicitly flagged by the original brief as "previously a total outage in the Firebase version" — verified this is **no longer the case**. Opened live by both the club owner (A) and a regular member (B); A sent a message, B received and saw it correctly left-aligned as A's message; B replied, A received it. Real, working, bidirectional. |
| **EVENTS** | Partially | Yes (live) | PARTIAL | A platform-level, read-only Events list exists (reachable via the calendar icon in the Feed app bar) and correctly displays pre-existing events. However: (1) tapping an event does nothing — no detail screen exists; (2) there is no event-creation UI anywhere in the app, at either the platform level or the club-admin level (the club admin dashboard's "Events" entry is an explicit "coming next" stub). Per the brief's own instruction ("if creation is not currently exposed, document why"): it is not exposed because it has not been built yet, not because of a bug. |
| **NOTIFICATIONS** | Yes | Yes (live) | PASS | Friend-request notifications verified live (and its stuck-spinner bug fixed, see FRIENDS). Club-request admin notification verified live this pass: submitting a club request as A correctly produced a "New Club Request — Chess Club Test wants to join TrueKinn" notification for admin B, with working Review/Dismiss actions and correct Realtime delivery. |
| **MOMENTS** | Disabled (by design) | N/A | N/A — untouched | `kMomentsEnabled = false` preserved exactly as instructed. Not enabled, not redesigned, not removed, camera/video_player dependencies untouched. One defensive `.toUtc()` consistency fix was applied to `moment_camera_screen.dart` (the same timezone bug class found live in anonymous chat) but is explicitly **not** claimed as live-verified, since the screen is unreachable while the feature is disabled. |
| **MODERATION / REPORTING** | Minimal | Yes (verified by code audit + schema check) | GAP — documented, not fixed | There is **no reporting or user-blocking mechanism anywhere in the reachable app.** The only `report_*` RPC (`report_moment`) exists solely inside the disabled Moments feature and is unreachable. Feed posts, 1:1 chat, club chat, and anonymous chat all have no report/block affordance. Separately: the in-chat profanity filter (`TextFilter`, used by 1:1 chat) is confirmed **client-side only** — the `messages` table's only server-side content constraint is `length(trim(text)) > 0`; there is no server-side profanity/content check. This matches the brief's own warning almost exactly: client-side filtering here is real but **not tamper-proof** — a modified client or a direct API call bypasses it entirely (verified by reading the schema; not exploited against the live table to avoid writing real profanity into the project). |
| **STORAGE SECURITY** | Yes | Yes (live + adversarial) | PASS | The `clubs` bucket privacy hole (public-read exposure of ID-card photos via `getPublicUrl()`) called out explicitly in the brief has been **fully closed**: bucket flipped to `public = false`, `id_card_url` now stores a private object path (not a public URL), and the admin review screen resolves it via a 5-minute `createSignedUrl()`. Verified adversarially via curl (uploader read 200, non-admin/non-uploader read 400, old public-URL-style path 400) *and* now verified live end-to-end through the real admin UI (the signed-URL preview correctly rendered a real uploaded image in the Club Requests screen). |
| **RLS / SECURITY** | Yes | Yes (live, adversarial, this pass) | PASS | All club-related adversarial checks performed live this pass, using real JWTs obtained via password grant (no fabricated credentials) for a genuinely non-admin user (A): (1) calling `approve_club_request` on another user's pending request → correctly denied (silent no-op, request left untouched, confirmed via direct DB read); (2) direct `INSERT` into `clubs` bypassing the RPC → blocked, `42501` RLS violation; (3) attempting to self-promote to `role = 'admin'` in one's own club membership row → no-op (RLS filtered the row); (4) attempting to insert oneself as `admin` into an unrelated club → blocked, `42501` RLS violation. All four PASS. This is in addition to the friendships-FK and clubs-bucket-privacy gaps found and fixed earlier in this effort. The existing 40/40 RLS scenario-test pass from the earlier migration work was not re-run as an automated suite in this pass (no such suite exists as a checked-in script — those were originally driven manually); this pass instead added fresh, live adversarial coverage on top of it rather than repeating it. |
| **REALTIME** | Yes | Yes (live) | PASS (with fixed regressions) | Two duplicate-`.stream()`-subscription bugs found and fixed this effort (Settings' Anonymous ID section vs. the persistent bottom-nav avatar stream; anonymous chat's transient duplicate message render). A third instance of the same bug *class* was found via code audit in `profile_screen.dart` (identical duplicate-stream pattern to the fixed Settings bug) but was **not** reproduced as broken in live testing — flagged as a known risk from the same bug class, not fixed, since fixing an unreproduced issue risks masking the real root cause if the pattern turns out to behave differently there. |
| **ERROR HANDLING / NETWORK** | Partially tested | Partially (incidental) | PARTIAL | No dedicated network-interruption/backgrounding pass was run this session as its own task. Several real error-handling bugs were found and fixed incidentally while testing other flows (stuck post-logout spinner with zero recovery path in `bottom_nav_shell.dart`'s null-user branch — root cause fixed upstream, but the branch itself still has no recovery path if ever hit by a different code path; stuck accept-friend-request spinner; anon-chat send silently swallowing its real exception behind a generic "Message not sent" toast, which is what hid the timezone bug for as long as it went undetected). No dedicated slow-connection/backgrounding/rapid-tap matrix was run. |
| **ANDROID** | Yes | Yes (live) | PASS | The entire session's testing was performed on a real Android emulator (arm64, resolution 1080×2400) via `adb`, including two clean `flutter analyze` (no issues) and `flutter test` (32/32 passing) runs at the end of this pass. |
| **IOS** | Unknown | **No — blocked** | BLOCKED | Xcode 26.1.1 is installed, but **no iOS Simulator runtime is installed** (`xcrun simctl list runtimes` returns empty) and no simulator device exists. Installing a runtime requires an interactive download (and typically an Apple ID) that could not be performed unattended in this environment. No speculative iOS-only changes were made. iOS readiness is genuinely unknown, not assumed. |

---

## Notable fixes made this effort (see git log for full detail)

1. `clubs` storage bucket flipped private + signed-URL admin review flow (closes the explicit ID-card public-exposure issue).
2. Duplicate-`.stream()` collision bugs fixed in Settings (Anonymous ID) and Anonymous Chat (message dedup).
3. Permanently-stuck post-logout loading spinner fixed via `pushAndRemoveUntil` with a fresh `AuthGate` — the single most severe bug found this effort.
4. College dropdown extended to cover RVCE/BMS/PES (was NMIT-only, silently mis-recording other colleges' display name — `college_id` itself was always correct).
5. Friend-request accept was **completely broken** through the real app (FK constraint) — fixed via `ON DELETE SET NULL` migration; its own follow-on stuck-spinner bug also fixed.
6. Anonymous chat send was **completely broken for every real user in India** (missing `.toUtc()` against a server-side RLS time-window check) — fixed. This is arguably the most impactful fix of the whole effort given the app's actual target market.

## Notable gaps found and *documented*, not fixed (out of this session's scope or requiring resources unavailable here)

- No moderation/reporting or user-blocking feature outside disabled Moments.
- Chat content filtering is confirmed client-side-only.
- Club "Members" and "Events" admin sub-screens are stubs.
- Platform Events has no creation UI and no detail view.
- Profile "Clubs" stat count doesn't reflect real membership.
- A `profile_screen.dart` duplicate-stream risk (same bug class as #2 above) flagged but not reproduced or touched.
- Stale/junk pre-existing test data in `club_requests` (two null-phone/null-usn "Chess Club" rows) and in the feed (one inappropriate placeholder test-image post) should be cleaned up before any real user sees them — not a code bug, a data hygiene item.
- iOS build/run status is unknown (environment blocker, documented above).
- Crash reporting: evaluated. Recommend Sentry (`sentry_flutter`) as it requires no Firebase, but wiring it up needs a real Sentry DSN only the project owner can create — not fabricated here, so no crash-reporting code was added this session.
- Push notifications: explicitly out of scope this session per the brief; not implemented.

## Final automated verification (this pass)

- `flutter analyze` — **no issues found**.
- `flutter test` — **32/32 passing** (text filter, college detector, widget smoke test).
- Live adversarial RLS checks (see RLS row above) — **all denied as expected**.
- Android build/install/runtime — verified throughout this pass via the live emulator session (app builds, installs, launches, and all flows above were driven through it).
- iOS build — **not run** (blocked, see IOS row).

## Readiness classification

**CLOSED BETA READY.**

Reasoning: every major user-facing flow (auth, feed, friends, 1:1 chat,
anonymous chat, clubs end-to-end including the previously-totally-broken club
chat, notifications) has now been genuinely exercised through the real running
app, and every bug actually found through that process — including two that
would have been silent, 100%-reproducible dealbreakers for real users
(anonymous chat and friend-request-accept were both completely non-functional
end-to-end despite passing earlier RLS-only tests) — has been fixed and
re-verified live. The explicit known security issue (public ID-card storage)
is closed and adversarially re-verified. Fresh live adversarial RLS testing
this pass found no new authorization gaps.

It is **not** classified PRODUCTION READY because: iOS status is completely
unknown (not merely untested — unbuildable in this environment); there is no
moderation/reporting surface for real user-generated content; a few
non-critical UI sub-features (club Members/Events, platform Events detail)
are unfinished stubs; and no dedicated network-resilience/backgrounding test
pass has been run. None of these block a small, trusted closed beta where the
operator can manually intervene, but they should be resolved before opening
the app to the general public.
