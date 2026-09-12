# Phase 6 — Product Bug Fixes: Executed + Remaining Gaps

**Status:** Client-side fixes executed (commit `66a9509`); architecture-level gaps documented for product decision.
**Date:** 2026-09-12
**Constraint honored:** Constraint 9 (if uncertain, STOP and document) and constraint 8 (no new product behavior without evidence). The items below are **documented only** — none required weakening a rule or inventing behavior.

---

## 1. Executed client-side fixes (commit `66a9509`)

| # | File | Fix | Evidence |
|---|---|---|---|
| 1 | `lib/feed/feed_screen.dart` | Removed fake presence badge ("🔥 N online") — `PresenceService.estimateOnline` was a hardcoded `5000` base + time-of-day curve + `Random()`, not real data | Feed app-bar previously painted fabricated user counts on every launch |
| 2 | `lib/feed/feed_screen.dart` | Added caption rendering below post image. Captions written by `add_post_screen.dart:56` (`'caption'`) and rendered on detail screen (`post_detail_screen.dart:27`) but were **invisible in the main feed** | Field contract verified via grep; feed now displays caption the same way detail does |
| 3 | `lib/anon/college_anon_chat_screen.dart` | Real 10s client-side cooldown. **Before:** every Firestore write failure mapped to "Slow down! 10s cooldown active." — misleading (the batch is rules-denied, see §2). **After:** genuine elapsed-since-last-send gate (`_lastSent`), and real failures show "Message not sent. Try again." | Root cause: `anon_chats/{id}/messages` has no rules match → implicit DENY on all writes |
| 4 | `lib/feed/comments_screen.dart` | Wrapped `_sendComment` in `try/catch/finally`; added `_sending` re-entry guard. **Before:** a rules-denied write left the send spinner/button stuck forever; rapid taps could double-send. **After:** error snackbar + spinner always resets; no double-send | Rules deny comment subcollection + updating another user's post |
| 5 | `lib/moments/moments_screen.dart` | Report failure snackbar: "You are offline. Report will sync later." → "Report failed. Please try again later." + `debugPrint(error)`. **Before:** permission denial was presented as a connectivity problem | Rules: `update` requires `resource.data.userId == request.auth.uid` — third-party report writes always denied |
| 6 | `post_detail_screen.dart`, `profile_screen.dart`, `friends_list_screen.dart` | Removed 4 unused imports + 2 unused locals (analyzer warnings left over from Phase 3 chain) | `flutter analyze` 49→ (down from 51), 0 errors |

**Gate:** `flutter analyze` → 0 errors (49 infos/warnings, all pre-existing). `flutter test` → all pass. `flutter build bundle --debug` → fresh kernel_blob.bin produced (mtime verified).

---

## 2. Documented gaps (architecture-level — NOT executed)

These need backend/data-contract work (rules, functions, or a product decision) and are logged here rather than guessed per constraints 8–9.

### GAP-1 — Notification `toUid` mismatch (HIGH severity, silent data loss)

- **Writer:** `lib/clubs/create_club_screen.dart:77-84` writes `notifications` doc with `{type, requestId, clubName, fromUid, createdAt, read}` — **no `toUid`**.
- **Reader:** `lib/notifications/notifications_screen.dart:40` queries `.where('toUid', isEqualTo: uid)`.
- **Consequence:** club-request notifications match **zero** queries → invisible to every user, forever. The intent (notify an admin/coordinator on a new club join request, see `requestId`) cannot work — there is no recipient field and no `club_join_requests` review screen (that screen was dead code from Phase 3).
- **Same-shape writters that DO set `toUid` (correct):** `friend_button.dart:36`, `chat_screen.dart:91` — 1:1 flows are shaped correctly.
- **Fix options (needs product decision):** (a) add `toUid` + dedicated `club_admin_dashboard`-style review surface (Phase 2 rules contract already lists `club_join_requests` as denied-by-default), or (b) drop the club_request notification from creation flow. Flagged to product owner.

### GAP-2 — N+1 user lookups (MEDIUM, read amplification)

- `lib/feed/post_user_header.dart:18-21` opens a **per-post** `users/{uid}` snapshot stream inside each feed card.
- `lib/feed/comments_screen.dart:162-166` (`_CommentTile`) fires a **per-comment** `users` `FutureBuilder.get()`.
- With a 30-post feed × ~10 comments, that's 300+ reads per screen render instead of 2 batched queries. Unique-read budget burns fast and renders slow on first paint.
- **Fix options (needs decision):** batch-fetch unique `userId`s in one `where(FieldPath.documentId, whereIn: [..])` query per screen, or denormalize name/photo onto posts/comments on write. Both are behavior-changing beyond this bug-fix pass — documented for Phase 8 recommendation.

### GAP-3 — Cross-college feed exposure (MEDIUM, product-policy question)

- **Writer:** `add_post_screen.dart` writes posts with `{userId, ...}` — **no `collegeId`**.
- **Reader:** `feed_screen.dart:139` streams `collection('posts')` with **no `collegeId` where-filter**.
- **Consequence:** the "Campus" feed shows posts from every college to every user; a post carries no college metadata. Phase 2 audit flagged the same accidental-allow pattern on posts/events/moments (public read).
- **Fix options (needs decision):** write `collegeId` at post creation (via `collegeIdForEmail`), filter feed by canonical id, add composite index. This is a *product-behavior change* (feed becomes college-scoped) — explicitly not implied by the current implementation, so documented, not executed.

### GAP-4 — Expired anon-chat writes denied by rules (HIGH, blocks feature)

- `lib/anon/college_anon_chat_screen.dart:74-96` builds a batch: `set` message doc + `update` user `lastAnonMessage`. Rules have **no match** for `anon_chats/*/messages` → entire batch denied. UI now reports it honestly ("Message not sent. Try again."), but the feature cannot write until rules are added additively (Phase 2 contract §. `anon_chats` match block) with `userId`/membership/`collegeId` validation.
- **This is the documented Phase 2 pending rules work — the client fix (#3) only removed the *misleading* message; it did not (and must not) weaken the deny-by-default posture.**

### GAP-5 — Anon-chat loading state is a blank screen (LOW)

- `college_anon_chat_screen.dart:181` returns `SizedBox()` while the message stream has no data → flash of empty pane. Minor polish, safe to fix in a later pass (a centered spinner).

### GAP-6 — Moments report success path (LOW, depends on GAP under Phase 4 §7)

- The success branch of `_MomentCard._report` (`moments_screen.dart:223-242`) is **unreachable** under current rules (ownership check rejects any third-party update). It also has an off-by-one smell: it `read`s back the doc after incrementing, but the increment is applied to a *different* doc read than the cached one. The proper fix (additive `reports` subcollection + Cloud Function) is Phase 4 §7.1; the client message is now honest on the failure path so this is only relevant once reporting actually works.

---

## 3. Verification record

- `flutter analyze`: **0 errors** (49 remaining issues; all pre-existing infos/warnings — down from 51; the 4 removed `unused_*` were from this pass).
- `flutter test`: all pass.
- `flutter build bundle --debug`: kernel_blob.bin regenerated at 22:18:35 (mtime inline with this pass).

*No Firestore rules, Supabase project configuration, or backend data were changed (constraints 4, 5, 6). All edits are additive/subtractive within the existing product surface.*