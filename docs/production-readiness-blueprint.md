# TrueKinn — Production Readiness Blueprint

**Generated:** 2026-09-14 (overnight productionization mission)
**Scope:** every major feature, end-to-end, traced against the code and rules currently on disk (not against prior reports). Classification legend:

| Code | Meaning |
|---|---|
| **A** | Production-usable today — correct, tested, reachable, no known gap |
| **B** | Fragile — works in the common case but has a real, reachable failure mode |
| **C** | Partial — the core loop works but a meaningfully-expected part is missing |
| **D** | Broken — the feature does not do what it claims to do |
| **E** | Stub — UI exists, wired to nothing (dead-UI) |
| **F** | Intentionally disabled — code exists, gated off on purpose |
| **G** | Missing and required — no code path exists, but production needs it |

This document is the living map this session's work (and the accompanying `docs/overnight-production-hardening-report.md`) is organized against. It supersedes prior phase reports as the single source of truth for "what is actually true right now" — those reports remain useful history but are not re-verified here.

---

## 1. Product Definition

TrueKinn is a private, college-only social app for four sanctioned Indian colleges (NMIT, RVCE, BMSCE, PES — `lib/auth/services/college_detector.dart`), gated at signup by verified Google-account email domain. Inside a college, a student can: post to a college-scoped feed, befriend other students, message 1:1 or in ephemeral anonymous college-wide rooms, join/run clubs with their own group chat, and (currently disabled) post ephemeral "Moments." A single hardcoded platform-admin account (`lib/core/admin.dart`) reviews club-creation requests and has cross-college oversight. There is no monetization, no admin web console, and no push-notification channel — all real-time behavior is Firestore listeners while the app is foregrounded.

The product's core value proposition — and its core trust boundary — is **college isolation**: a user should only ever see people, posts, and chat rooms from their own verified college (with the platform admin as the sole exception). Nearly every rules-layer decision in this codebase exists to enforce that boundary; nearly every bug found this session and in prior sessions has been a place where that boundary was accidentally absent (unfiltered queries, missing `collegeId` checks) or where a legitimate action was accidentally *denied* by an overly-blunt boundary check (the `resource.data` null-dereference bug class, see §10).

## 2. Feature Inventory

| # | Feature | Classification | One-line status |
|---|---|---|---|
| 1 | Signup / email-domain gate | A | Works; Google Sign-In only, real OAuth (no emulator bypass) |
| 2 | Profile bootstrap (auth_gate.dart) | A | Fixed Phase 20 (users.read null-deref); verified live on-device |
| 3 | Profile setup / edit | A | Works |
| 4 | College-scoped feed (posts) | A | Works; college isolation enforced at rules layer |
| 5 | Post creation | A | Works |
| 6 | Likes | A | Works, uid-keyed, one-per-user |
| 7 | Comments | A | Works |
| 8 | Search / user directory | A | Fixed Phase 18 (N+1 re-subscribe bug); college-scoped |
| 9 | Friends — send/accept/decline request | A | Fixed Phase 18 (dead notification, consent hole); Phase 20/21-adjacent client workaround for null-deref |
| 10 | Friends — friend button relationship state | A | Already defensively coded against the null-deref bug class |
| 11 | 1:1 chat | A | Fixed Phase 18 (unsorted-members bug); defensively coded against null-deref |
| 12 | Club creation request + admin review | A | Works, transactional, rules-matched |
| 13 | Club browse (Your Clubs / Explore) | B | Works; dead `isAdmin` prop in Explore grid (cosmetic) |
| 14 | Club join request + admin approval | A | Works, transactional |
| 15 | Club chat (group chat) | A | Fixed Phase 18 (parent doc rule entirely missing — total outage); works now |
| 16 | Club membership read (`_RoleActions`) | A | **Fixed this session** (Phase 21) — null-deref on non-member's first view |
| 17 | Club posts/announcements | G | Rules exist for it; zero UI; not reachable at all |
| 18 | Leave a club | G | No UI, rules don't even permit self-delete |
| 19 | Kick a club member | E | Dashboard card is a dead SnackBar stub |
| 20 | Edit club details | G | No UI; rules permit it |
| 21 | Delete a club | G | No UI; rules permit it; no cascade-delete function either |
| 22 | Club-scoped events (from admin dashboard) | E | Dashboard card is a dead SnackBar stub |
| 23 | Event creation | C | Write path works; nothing can ever read it back (see §5) |
| 24 | Event browsing | G | No collection read anywhere in the app |
| 25 | Event RSVP | G | No schema, no UI |
| 26 | Notifications — club_request / friend_request | A | Creation and rules-matching both correct |
| 27 | Notifications — read/unread state | D | `read` field written, never read anywhere — dead data |
| 28 | Notifications — cleanup/TTL | G | No Cloud Function; accumulates forever |
| 29 | Anonymous college chat | A | Strict college isolation, TTL enforced at rules + Cloud Function |
| 30 | Moments — capture/upload | F | Restored Phase 17, correctly gated off (`kMomentsEnabled = false`) |
| 31 | Moments — feed scoping | F/D* | Gated off; if ever re-enabled, has no college/visibility filtering (see §6) |
| 32 | Moments — report flow | F/D* | Gated off; if ever re-enabled, always fails (owner-only rule, no carve-out) |
| 33 | Cloud Functions — anon message cleanup | A | Works, scheduled every 1 min |
| 34 | Cloud Functions — friendsCount counter | A | Works, transactional trigger |
| 35 | Club membersCount counter | A | Works, client-side transaction (not a Cloud Function, but correct) |
| 36 | Push notifications | G | Explicitly out of scope this mission (Part 11) — documented, not built |
| 37 | Android build | A | Fixed Phase 19; structurally sound; blocked only on a real `google-services.json` (see §14) |
| 38 | Android release signing | G | No `key.properties`; falls back to debug signing (documented, cannot fabricate) |
| 39 | iOS build | **A (verified this session)** | Real `GoogleService-Info.plist` present, bundle ID matches; `flutter build ios --simulator --no-codesign` succeeded (see §15) |
| 40 | Firestore security rules | A | 164/164 rules-emulator tests pass after this session's sweep (§10) |
| 41 | Content moderation (text filter) | B | Client-side keyword filter only; trivially bypassable, no server-side enforcement |

\* Moments is intentionally-disabled (F) as a whole per explicit instruction, but its *code*, if ever re-enabled without further work, contains genuine D-class bugs — flagged so a future "just flip the flag" decision doesn't accidentally ship them.

## 3. Production-Grade Features (A)

These work correctly today, are reachable through normal navigation, are covered by passing tests (rules-level, and/or verified live on-device this mission or a prior one), and have no known gap that would block real users. Full detail already exists in prior phase reports and in this session's own investigation; no further action needed for GA on these specifically:

Auth/bootstrap (#1–3), feed core (#4–7), search (#8), friends core (#9–10), 1:1 chat (#11), club lifecycle core (#12, 14, 15, 16), notification creation (#26), anonymous chat (#29), both Cloud Functions (#33–34), club counters (#35), Firestore rules as a whole (#40, after §10's fix), and — newly confirmed this session — the iOS build (#39).

## 4. Fragile Features (B)

### 4a. Club Explore grid — dead `isAdmin` prop
- **CURRENT STATE:** `clubs_screen.dart:194-229` computes `isAdmin` from a hardcoded email allowlist and threads it into `_ClubCard`, which never reads it (`clubs_screen.dart:277-387`). No behavioral effect; real per-club admin UI is correctly driven elsewhere by the `club_members` role doc.
- **REQUIRED FOR PRODUCTION:** No functional requirement — this is dead code, not a missing feature.
- **ACTUAL GAP:** Vestigial/misleading code; a future maintainer could reasonably assume it does something.
- **PRIORITY:** P3
- **RECOMMENDED FIX:** Delete the dead `isAdmin` computation and prop, or wire it to something real if a "global admin badge on club cards" feature is actually wanted. Zero risk either way.

### 4b. Content moderation — client-side only
- **CURRENT STATE:** `lib/moderation/text_filter.dart` (82 lines) is a keyword-based filter invoked client-side before 1:1 chat sends, club chat sends, and anon chat sends. It is not enforced anywhere in `firestore.rules` — a modified/rooted client, or a direct API call, bypasses it entirely.
- **REQUIRED FOR PRODUCTION:** For a private college app with no monetization and known cohort, client-side moderation is a reasonable v1 given the alternative (a moderation Cloud Function) is real infrastructure work — but this is a genuine trust boundary gap: any determined bad actor can send anything.
- **ACTUAL GAP:** No server-side content check at all; also no user-facing report/block mechanism for chat messages (only Moments has a report flow, and it's broken — see §6).
- **PRIORITY:** P2 (not blocking for a closed/internal beta with a small known cohort; becomes P0 before any open release)
- **RECOMMENDED FIX:** Document as a known, accepted risk for internal/closed beta. Before wider release: move the filter (or a stronger one) into a Cloud Function `onCreate` trigger that can delete/flag violating messages after the fact (rules can't run arbitrary string-matching against a growing blocklist cheaply), and add a user-facing "report message" action for 1:1/club chat (parity with the existing, currently-broken, Moments report flow).

### 4c. Club chat double-tap guard is state-only, not UI-disabled
- **CURRENT STATE:** `club_chat_screen.dart`'s send button remains enabled during a send (`onPressed: _send` unconditional); an internal `_sending` flag makes a rapid double-tap a no-op, with only an icon swap as feedback.
- **REQUIRED FOR PRODUCTION:** Consistent with other send-guards in the app (1:1 chat's `_InputBar` has the same pattern, acceptable).
- **ACTUAL GAP:** Cosmetic only — no duplicate-message risk, just slightly less clear feedback than a fully-disabled button.
- **PRIORITY:** P3
- **RECOMMENDED FIX:** Optional polish — disable the button while `_sending` is true, matching the icon swap.

## 5. Incomplete Features (C)

### 5a. Events — write-only, no read path
- **CURRENT STATE:** `create_event_screen.dart` fully implements event creation (validation, media upload, college stamping, rules-compliant write). Confirmed via exhaustive grep: **no file in `lib/` ever reads from the `events` collection.** There is no list screen, no detail screen, no "Events" tab. `firestore.indexes.json` has no composite index for `events` either, consistent with zero queries ever being issued. The `eventLink` field written at creation (`create_event_screen.dart:30-31`) points at a placeholder domain (`demo.yourcollegeapp.com`) that isn't this app.
- **REQUIRED FOR PRODUCTION:** An event that can never be viewed again — by anyone, including its creator — is not a shippable feature; it's a write with no purpose. Either a browse/detail screen ships, or event creation should be hidden from the UI until one does.
- **ACTUAL GAP:** Entire read side (list, detail, RSVP) is missing. This is the single clearest "write with no read path" finding in the whole audit.
- **PRIORITY:** P1 (either ship the read side, or pull the create entry point so users can't create something they can never see again)
- **RECOMMENDED FIX:** Minimum viable read side: a college-scoped `events` list screen (`where('collegeId','==',myCollegeId).orderBy('startDate')`) plus a detail view — mirrors the existing posts-feed pattern closely enough to reuse most of its plumbing. Needs a new composite index (`collegeId ASC, startDate ASC/DESC, __name__`). If that's out of scope for this release, the pragmatic short-term fix is to remove the "Create Event" entry point from `add_create_selector_sheet.dart` so the app stops silently discarding user-created content.

### 5b. Club join-request review — N+1 profile reads
- **CURRENT STATE:** `club_join_requests_screen.dart`'s `_RequestCard` does a non-cached `FutureBuilder` `.get()` on `users/{userId}` per pending-request card.
- **REQUIRED FOR PRODUCTION:** Functionally correct; only a scale concern for clubs with large pending-request queues.
- **ACTUAL GAP:** No batching/caching of applicant profile reads.
- **PRIORITY:** P3
- **RECOMMENDED FIX:** Not urgent given expected queue sizes (tens, not thousands); revisit if a club admin reports slow loading. See also §12 (performance).

## 6. Broken Features (D)

### 6a. Notification read/unread state is dead data
- **CURRENT STATE:** Both notification-writing call sites (`create_club_screen.dart:89`, `friend_service.dart:99`) set `read: false`. Grep across all of `lib/` confirms this field is **never read, filtered on, or updated to `true` anywhere.** No unread badge, no `where('read', ...)` query.
- **REQUIRED FOR PRODUCTION:** A notification list with no unread/read distinction functions (it shows all notifications), so this isn't a hard blocker, but it means the app can never show an unread-count badge — a standard, expected affordance.
- **ACTUAL GAP:** Missing: mark-as-read on tap/view, unread-count query, and a visual unread indicator.
- **PRIORITY:** P2
- **RECOMMENDED FIX:** On `notifications_screen.dart`'s tile tap/dismiss paths, `update({'read': true})` (already rules-permitted — recipient-only update). Add an unread-count `StreamBuilder` (`where('toUid',uid).where('read','==',false)`) for a badge. Needs a new composite index (`toUid ASC, read ASC, createdAt DESC`).

### 6b. Friend-request notifications never auto-dismiss
- **CURRENT STATE:** `club_request` notifications have an explicit manual "Dismiss" button (`notifications_screen.dart:145-157`). `friend_request` notifications only get deleted as a side effect of Accept/Reject (`friend_service.dart`'s `_deleteRequestNotifications`). If a user simply never taps Accept/Reject, the notification is permanent.
- **REQUIRED FOR PRODUCTION:** Every notification type needs a way to leave the list.
- **ACTUAL GAP:** No manual dismiss control on the friend-request tile.
- **PRIORITY:** P2
- **RECOMMENDED FIX:** Add a dismiss/swipe action to the friend-request tile that deletes just that notification (not the underlying `friend_requests` doc — a user should be able to clear the notification without withdrawing/declining the actual request). Small, isolated change.

### 6c. No cleanup/TTL for notifications, club_requests, or friend_requests
- **CURRENT STATE:** The only scheduled Cloud Function is `cleanupExpiredAnonMessages`. Nothing prunes stale `notifications`, resolved `club_requests`, or expired `friend_requests`.
- **REQUIRED FOR PRODUCTION:** Not urgent at current/expected scale, but unbounded growth in a collection with a `.limit(100)` client query (§7f below) means very active users could eventually lose visibility into their own older items.
- **ACTUAL GAP:** No retention policy anywhere for these three collections.
- **PRIORITY:** P2
- **RECOMMENDED FIX:** A monthly-or-so scheduled function deleting `notifications` older than e.g. 90 days (mirrors the `cleanupExpiredAnonMessages` pattern already in `functions/index.js`). Not urgent for closed beta.

### 6d. Moments — feed has no college/visibility scoping (currently unreachable, but real)
- **CURRENT STATE:** `moments_screen.dart`'s feed query has **no `where` clause at all** — every non-expired moment from every college is shown to every user, and the `visibility` field ('college' vs 'friends') captured at creation is never read anywhere. `firestore.rules` moments block (`allow read: if true`) doesn't enforce `collegeId` either — this is a data-layer gap, not just a query oversight; a stricter query alone wouldn't fully close it without a matching rules change.
- **REQUIRED FOR PRODUCTION:** Moments is intentionally disabled (`kMomentsEnabled = false`, `feed_screen.dart:18`) and **this mission explicitly forbids touching that** — this entry exists purely so that a future decision to re-enable Moments doesn't ship this privacy bug by surprise.
- **ACTUAL GAP:** Query has no `collegeId`/`visibility` filter; rules have no `collegeId` check either.
- **PRIORITY:** P1, but **only if/when Moments is re-enabled** — P4/no-action while it stays off.
- **RECOMMENDED FIX (for whenever Moments is revisited, not this mission):** Rules: add `resource.data.collegeId == userCollege()` to `moments.read` (mirroring `posts.read`). Client: filter `moments_screen.dart`'s query by `collegeId`, and either enforce `visibility` at the rules layer too or remove the selector from `moment_preview_screen.dart` if it's staying decorative.

### 6e. Moments — report flow always fails (currently unreachable, but real)
- **CURRENT STATE:** `_MomentCard._report` (`moments_screen.dart:229-266`) tries to `update({'reportsCount': increment(1)})` on a moment it doesn't own. `moments.update` rule is owner-only with no carve-out (unlike `posts.update`, which explicitly allows a `likesCount`/`commentsCount`-only diff from a non-owner). Every third-party report attempt fails with `permission-denied`, unconditionally — the code even has a comment acknowledging this.
- **REQUIRED FOR PRODUCTION:** Same caveat as 6d — Moments is off, this is pre-positioned for whenever it's revisited.
- **ACTUAL GAP:** Rule has no non-owner carve-out for a `reportsCount`-only diff.
- **PRIORITY:** P4 while disabled; P1 if re-enabled (a report button that always silently fails is worse than no report button).
- **RECOMMENDED FIX (deferred, not this mission):** Add a `reportsCount`-only diff carve-out to `moments.update`, mirroring the existing `posts.update` pattern exactly.

## 7. Intentionally-Disabled Features (F)

### 7a. Moments (whole feature)
- **CURRENT STATE:** Fully implemented (capture, upload, feed, my-moments, delete, report-UI), gated off via `kMomentsEnabled = false` in `feed_screen.dart:18`, per explicit prior instruction (restored Phase 17 after an unauthorized deletion, deliberately kept disabled rather than either re-deleted or shipped). Verified unchanged this session — no edits made to Moments code or the flag, per this mission's explicit instruction (Part 12).
- **REQUIRED FOR PRODUCTION:** Not required for this release; product decision to re-enable is out of scope for this mission.
- **ACTUAL GAP:** N/A — working as intentionally configured. See §6d/6e for the real bugs that exist *inside* the disabled code, so they're known before any future re-enable decision.
- **PRIORITY:** N/A
- **RECOMMENDED FIX:** None for this mission. If a future session re-enables it, fix 6d and 6e first.

### 7b. Push notifications
- **CURRENT STATE:** No `firebase_messaging` or any push dependency in `pubspec.yaml`; no FCM token registration, no notification channel, no background handler. All "notifications" in this app (`notifications` collection) are in-app-only, visible solely when the app is foregrounded and the user opens the Notifications screen.
- **REQUIRED FOR PRODUCTION:** A social app with friend requests and club activity strongly benefits from push — a user who doesn't open the app won't know they got a friend request. Not a hard blocker (in-app notifications still work when the app is open), but a significant retention/engagement gap.
- **ACTUAL GAP:** Entire push pipeline — FCM setup, APNs cert/key for iOS, token storage on the user doc, a Cloud Function to send on `notifications.onCreate`, foreground/background handlers, notification permission prompt UX.
- **PRIORITY:** P2 (real gap, but explicitly out of scope for this mission — Part 11 instructs documenting only, not building)
- **RECOMMENDED FIX:** Not implemented this mission per explicit instruction. When undertaken: `firebase_messaging` + platform setup (APNs key upload in Firebase console — a credential only the user can create), token field on `users/{uid}`, a `notifications.onCreate` trigger that sends via FCM, and standard foreground/background message handling.

## 8. Security Requirements

- College isolation must hold for every collection that carries a `collegeId`: posts, events, anon_chats (rules-verified for all three; §10 sweep found no cross-college leak).
- No client should ever be able to write another user's counters, forge another user's identity on a message/post/comment, or read another user's private data (friends-only chat, notifications, own-membership rows) — verified this session for `club_members` (§10 fix); all other collections were already correctly scoped as of Phase 18's security pass.
- **Gap (see §4b):** content moderation is client-only, bypassable by a modified client. Acceptable for closed beta with a known, small, verified-email cohort; must be revisited before any broader release.
- **Gap:** no report/block mechanism for 1:1 or club chat abuse (Moments has one, and it's broken — §6e). For a closed beta among known students this is a lower-severity gap than it would be for a public launch, but should exist before wider release.
- No secrets are committed to the repo (`android/key.properties`, real `google-services.json` for Android, and any release keystore are all correctly absent/git-ignored rather than fabricated, per this mission's explicit "no fabricated credentials" instruction).

## 9. Reliability Requirements

- Every async data flow that reaches production users should have loading/success/empty/error/retry states. Phase 18 closed the majority of these gaps; this session found no new ones in the areas re-audited (clubs, events, notifications, moments) beyond the already-cataloged Moments upload path (§ below).
- **Gap:** `moment_camera_screen.dart`'s `_uploadMoment`/`_openPreview` chain (`:117-179`) has no try/catch — a failed Supabase upload or Firestore write throws uncaught. Low priority only because Moments is disabled; would need fixing before any re-enable.
- The `_BootstrapError` retry screen (`auth_gate.dart`) correctly distinguishes a transient bootstrap failure from "onboarding incomplete" — this was itself a Phase-era fix and remains correct.
- Chat and friends flows already have documented, tested client-side workarounds for the Firestore "nonexistent-doc dereference throws" behavior (`chat_screen.dart`, `friend_service.dart`, `friend_button.dart`) — these are the model other spots should follow if a similar issue is found later.

## 10. Backend Requirements (Firestore Rules — this session's primary focus)

### The bug class
Firestore denies `permission-denied` (rather than gracefully evaluating to "doesn't exist") whenever a rule's `allow read`/`allow get` condition dereferences `resource.data` (or a `get(...).data` field) and the target document doesn't exist. This has now bitten **three** collections across this project's history:
1. `users/{userId}` — every new signup's bootstrap read, fixed Phase 20 (found via live on-device testing).
2. `chats/{chatId}` and `friends/{friendId}` — already defended client-side (documented, tested workarounds; the rules themselves still throw, but every call site treats any error as "doesn't exist," which is safe because both IDs are always derived from the caller's own uid).
3. `club_members/{memberId}` — **found and fixed this session** (§ below). `club_profile_screen.dart`'s `_RoleActions` widget live-listens on `club_members/{clubId}_{myUid}` for every club rendered; for the common case (caller hasn't joined), the doc doesn't exist, and the old rule's unguarded `resource.data.userId` dereference killed the listener on a permission error instead of cleanly observing "not a member."

### This session's systematic sweep
Every `match` block in `firestore.rules` (20 total) was read in full and checked against: (a) does this rule's `allow read` dereference `resource.data` or a `get(...).data` field, and (b) is there a realistic client sequence where the target document legitimately doesn't exist yet? Findings:

| Match block | `resource.data` dereference in read rule? | Nonexistent-doc reachable via normal flow? | Action |
|---|---|---|---|
| `users` | Yes | Yes (new signup) | **Already fixed, Phase 20** |
| `posts`, `likes`, `comments` | Yes (posts; `postCollege()` for likes/comments) | Only via a delete-race (post deleted between feed snapshot and interaction) — not a systemic "always missing" case | No fix — correct to deny; documented, not changed, per explicit "don't blindly modify every occurrence" instruction |
| `events` | Yes | No read path exists in the app at all (§5a) | No fix needed (unreachable either way) |
| `club_requests` | Yes | No by-ID get of a possibly-nonexistent doc in the client | No issue found |
| `notifications` | Yes | No by-ID get of a possibly-nonexistent doc; all access is via list-query or refs from an existing query result | No issue found |
| `club_members` | Yes | **Yes** — `_RoleActions` checks the caller's own possibly-nonexistent membership row on every club view | **Fixed this session** (see below) |
| `club_join_requests` | Yes | No by-ID get of an unknown-existence doc (list-query only) | No issue found |
| `chats` + `messages` | Yes (`isChatMember()`) | Yes (brand-new conversation) | **Already defended client-side**, `chat_screen.dart:47-84`, documented and tested in a prior phase — no rules change made (the client workaround is correct and sufficient; treating this as already resolved) |
| `friends` | Yes | Yes (any not-yet-friends pair — the common case) | **Already defended client-side**, `friend_service.dart:23-37` and `friend_button.dart:41-51`, documented and tested in a prior phase |
| `friend_requests` | Yes | No by-ID get of an unknown-existence doc | No issue found |
| `club_chats` + `messages` | No (`isClubMember()` uses `exists()`, which returns false cleanly rather than throwing) | N/A | No issue — this pattern is actually the *correct* idiom, contrast with `club_members.read`'s old direct `resource.data` check |
| `clubs` + `clubs/posts` | `clubs.read`/`posts.read` are `if true` (no dereference at all); `clubs.update/delete` dereferences `resource.data.admins` but only ever called against an existing club from a query result | No issue | No issue found |
| `moments` | Yes (`update`/`delete`) | Only reachable while disabled (§6e) | No fix — out of scope while Moments stays off |
| `anon_chats` + `messages` | `anon_chats.read` doesn't dereference `resource` at all (uses `isOwnCollegeRoom()`, which only reads the *caller's own* user doc, guaranteed to exist post-bootstrap); `messages.read` dereferences `resource.data.expiresAt` but only via a live query, not a by-ID get | No issue | No issue found |

### The fix (this session)
`firestore.rules`'s `club_members.read` rule now guards every `resource.data` dereference with `resource != null`, and adds a `memberId.matches('.*_' + request.auth.uid + '$')` clause that grants "read your own memberId" regardless of existence — provably equivalent to the old behavior for existing docs (same `resource.data.userId` check, just guarded), and now gracefully permissive (not throwing) for the common "haven't joined yet" case. Two new regression tests (`m7`, `m8` in `functions/test-rules/club_request_rules.test.js`) verify: your own nonexistent row is readable; someone else's nonexistent row is still denied (no enumeration opened up). **All 164 rules-emulator tests pass** against a freshly-restarted emulator.

- **PRIORITY:** P0 — this was a real, common-path bug silently breaking a live feature's UI state (club chat/admin visibility) for the majority case (non-members). **Fixed.**

## 11. Android Requirements

- **CURRENT STATE:** Structural Gradle issues (plugin-classloader isolation, missing Flutter Gradle plugin wiring, missing plugin declarations) were fully root-caused and fixed in Phase 19 — the build now correctly reaches the point of requiring a real, non-fabricated `android/app/google-services.json`, which is absent (confirmed again this session — `find android/app -iname google-services.json` returns nothing). `android/key.properties` is also absent, so release builds fall back to debug signing (`android/app/build.gradle.kts:77-81`) rather than failing — correct interim behavior, not shippable to Play Store as-is.
- **REQUIRED FOR PRODUCTION:** A real `google-services.json` downloaded from the Firebase console for this project, and a real upload keystore + `key.properties` for Play Store signing.
- **ACTUAL GAP:** Both files require credentials only the project owner can legitimately obtain (Firebase console access, a newly-generated signing keystore) — cannot be fabricated per this mission's explicit instruction. `minifyEnabled`/`isShrinkResources` are both `false` (Phase 12/13 decision, documented, not a bug — larger APK but no shrink-related breakage risk).
- **PRIORITY:** P0 for any real device distribution (the app literally cannot initialize Firebase without the real config file); P1 for Play Store specifically (release signing).
- **RECOMMENDED FIX:** User action required — cannot be automated: (1) download `google-services.json` from the Firebase console for the `navdeep-college-app` project (confirmed as the correct project ID via `ios/Runner/GoogleService-Info.plist`'s `PROJECT_ID` field) and place it at `android/app/google-services.json`; (2) generate a release keystore (`keytool -genkey ...`) and create `android/key.properties` per the standard Flutter signing guide. Both are already correctly wired to be picked up automatically once present (`build.gradle.kts`'s `hasReleaseKeystore` check).

## 12. iOS Requirements

- **CURRENT STATE (verified this session, not merely carried over from a prior report):** `ios/Runner/GoogleService-Info.plist` exists and is a real (non-placeholder) file — `PROJECT_ID: navdeep-college-app`, `BUNDLE_ID: com.navdeep.collegeapp.collegeApp`. This bundle ID matches `PRODUCT_BUNDLE_IDENTIFIER` in `Runner.xcodeproj/project.pbxproj` exactly (checked both the `Runner` and `RunnerTests` targets, all build configs). `Podfile`/`Podfile.lock` are both present. Xcode 26.1.1 and CocoaPods are installed on this machine. **`flutter build ios --simulator --no-codesign` was run this session and completed successfully** — confirming the project actually compiles and links against the real Firebase config, not just that the files look superficially correct. (No iOS Simulator runtime is installed on this machine — `xcrun simctl list devices` returns none — so a live on-device/simulator run of the app itself was not performed; only the build.)
- **REQUIRED FOR PRODUCTION:** A code-signing identity + provisioning profile (or App Store Connect API key for CI) to produce a distributable/TestFlight build; an Apple Developer Program enrollment tied to the bundle ID above.
- **ACTUAL GAP:** No signing identity configured in this environment (expected — that's a per-developer/CI credential, not something to fabricate or discover from the repo). Otherwise, the iOS side is in materially better shape than the Android side was before Phase 19 — no structural build issues found.
- **PRIORITY:** P1 (signing is required for any real distribution, but the hard part — "does this project even compile against real config" — is now verified working)
- **RECOMMENDED FIX:** User action: open the project in Xcode, sign in with an Apple ID enrolled in the Developer Program, let Xcode manage signing (or configure manual signing/CI with a distribution certificate), and archive. No code changes needed on the current evidence.

## 13. Testing Requirements

- **CURRENT STATE:** 164 Firestore-rules tests across 5 files (`functions/test-rules/*.test.js`) run against the real Firestore emulator — this is the project's primary and most trustworthy test layer, since it exercises the actual security boundary. Dart-side test coverage is thin: exactly 3 files (`test/widget_test.dart`, `test/college_detector_test.dart`, `test/text_filter_test.dart`) — no widget/integration tests for chat, feed, friends, or clubs flows.
- **REQUIRED FOR PRODUCTION:** Rules coverage is strong and should remain the primary regression net for security-relevant behavior. Some minimum of Dart-side integration testing (at least smoke-level) reduces regression risk in UI logic that rules tests structurally cannot cover (e.g. the `_RoleActions` StreamBuilder's actual rendering behavior, not just the rule that gates its data).
- **ACTUAL GAP:** No integration/widget tests for any of the app's primary flows.
- **PRIORITY:** P2
- **RECOMMENDED FIX:** Not undertaken this mission (out of scope vs. the rules-sweep priority this mission set). Lowest-effort highest-value addition: a widget test for `auth_gate.dart`'s bootstrap flow (the exact class of bug that broke every signup in Phase 20) and one for `_RoleActions` (the class of bug fixed this session) — both are cheap to write with `fake_cloud_firestore` or a Firestore emulator-backed widget test, and both guard against the two most severe bugs found this project's history.

## 14. Observability Requirements

- **CURRENT STATE:** No crash reporting (no Crashlytics or equivalent), no analytics, no structured logging beyond `debugPrint` calls scattered through the client (e.g. `auth_gate.dart:137`) and `console.log` in Cloud Functions. No error-rate dashboard, no alerting.
- **REQUIRED FOR PRODUCTION:** At minimum, crash reporting before any real-user release — otherwise a bug like the Phase 20 signup-breaking rules bug would have gone undetected except by a user complaint (it was in fact found only through deliberate live-device testing, not through any signal the app itself surfaces).
- **ACTUAL GAP:** Entire observability stack.
- **PRIORITY:** P1
- **RECOMMENDED FIX:** Not undertaken this mission. `firebase_crashlytics` is the natural fit given the project already depends on `firebase_core`; wrap the app in its error handlers and forward `FlutterError.onError`/`PlatformDispatcher.instance.onError`. Cloud Functions already log to Cloud Logging by default (visible in the Firebase console) — no change needed there beyond periodically checking it.

## 15. Launch Requirements

Minimum bar to let real users onto the app (in priority order):
1. **P0 — Android:** real `google-services.json` (§11) — the app cannot start on Android without it.
2. **P0 — Backend:** the `club_members.read` fix (§10) is committed locally; needs eventual push+deploy of `firestore.rules` for the fix to take effect for real users.
3. **P1 — iOS:** a real signing identity for distribution (§12) — build itself already verified working.
4. **P1 — Android:** release keystore + `key.properties` for Play Store (§11).
5. **P1 — Observability:** crash reporting at minimum (§14), so post-launch issues surface without relying on user reports.
6. **P1 — Events:** either ship a read path or pull the dead-end create entry point (§5a).
7. **P2 — Notifications:** read/unread state, dismiss-on-friend-request, cleanup (§6a–6c).
8. **P2 — Moderation:** acceptable for closed/internal beta as-is; needs a server-side layer before any open release (§4b).

Given the current state, this mission's overnight hardening report (`docs/overnight-production-hardening-report.md`) rates the app for **internal/closed beta with a known cohort**, not open production — see that document for the full conservative rationale.

## 16. Post-Launch Improvements

Lower-priority items that don't block any launch tier but are worth tracking:
- Club-posts/announcements subcollection (§2 #17) — rules already exist, could ship a UI later.
- Club leave/kick/edit/delete member-management screens (§2 #18–21) — currently no lifecycle management beyond create/join.
- Club-scoped events entry point (§2 #22) — currently a dead stub; either build it or remove the card.
- Report/block mechanism for chat abuse, beyond the (currently broken, currently disabled) Moments report flow.
- N+1 profile-read cleanup in club join-request review (§5b) if queue sizes grow.
- Dart-side integration test suite (§13).
- Push notifications (§7b), once product prioritizes retention/engagement work.

## 17. Final Production Checklist

- [x] Moments restored per prior instruction, correctly kept disabled
- [x] Friend request flow fixed (notification, consent, deterministic IDs)
- [x] Club chat total-outage bug fixed
- [x] Search N+1 performance bug fixed
- [x] Android build structurally fixed (Phase 19)
- [x] `users.read` bootstrap bug fixed and live-verified (Phase 20)
- [x] Systematic rules sweep for the same bug class — one more instance found and fixed (`club_members.read`, Phase 21, this session)
- [x] iOS build config verified with a real compile (this session — new)
- [ ] Real `android/app/google-services.json` in place (user action required)
- [ ] Real Android release keystore + `key.properties` (user action required)
- [ ] iOS signing identity configured for distribution (user action required)
- [ ] Crash reporting wired up
- [ ] Events feature given a read path, or its create entry point removed
- [ ] Notification read/unread + cleanup implemented
- [ ] Server-side (or at least stronger) content moderation before any open release
- [ ] `firestore.rules` changes from this session deployed (currently committed locally only, per explicit "do not push" instruction for this mission)

---

*This blueprint will be updated as the remaining parts of the overnight mission (live multi-account walkthrough, failure injection, data-integrity audit, performance audit) proceed. See `docs/overnight-production-hardening-report.md` for the full narrative report and final readiness rating once complete.*
