# College Isolation & Firestore Contract Review (task #26)

Date: 2026-09-13 · Branch: main · Baseline commit: 467b52b

This is the **review** deliverable for pre-sprint task #26. Each finding maps to a
sprint phase that performs the enforcement fix (marked `→ Phase N`). Verified in
this session: anon chat (#23/#24) and the club-request contract (#25/#29) —
both closed with emulator-tested rules.

## Identity model (verified consistent)

- `users.collegeId` = canonical slug (nmit / rvce / bms / pes / unknown),
  derived from the Google-verified email. Mirrored server-side by
  `collegeIdFromEmail()` in `firestore.rules`; written only via
  `collegeIdForEmail(email, fallbackCollege)` (profile_setup_page.dart:144) and
  immutable in rules (users.update rejects a changed collegeId).
- `users.college` = display label only.
- Risks carried into later phases:
  - profile_setup_page `_colleges` list has only two entries ("NMIT", "Other");
    the canonical collegeId is email-authoritative, so isolation survives, but
    the display label is wrong for non-NMIT sanctioned domains.
    → Phase 10 (auth/profile).

## Enforcement matrix

| Collection | Rules today | Client write stamps collegeId | Client read filters college | Status |
|---|---|---|---|---|
| `users` | read signed-in; create/update owner + immutable collegeId | yes (email-derived) | n/a | ✅ contract OK |
| `anon_chats`/`messages` | strict own-college room, TTL, sender checks | yes | own-college room only | ✅ FIXED this session (18 cases green) |
| `notifications` | recipient-only read/delete; create requires toUid≠sender | yes (`toUid` added) | toUid == uid | ✅ FIXED this session (27 cases green) |
| `club_requests` | owner create(pending), admin review, owner reads own | (ownerUid) | — | ✅ FIXED this session |
| `club_members` | read signed-in; admin/platform write | — | — | ✅ FIXED this session |
| `posts` | read true | **no collegeId** | **no filter** | ❌ LEAK → Phase 4 / #31 |
| `posts/{id}/likes` | implicit DENY | — | — | 🔴 BROKEN (like is denied) → Phase 4 / #31 |
| `posts/{id}/comments` | implicit DENY | — | — | 🔴 BROKEN → Phase 4 / #31 |
| `moments` | read true | yes (collegeId) | **no filter** (reads all) | ⚠️ stamped but LEAK → Phase 8 / #35 |
| `clubs` | read true; create/update admin | no collegeId | no filter | ⚠️ global clubs → Phase 7 / #34 |
| `club_chats` | implicit DENY | — | — | 🔴 BROKEN → Phase 7 / #34 |
| `chats` + `messages` | implicit DENY | — | — | 🔴 BROKEN (1:1 chat) → Phase 6 / #33 |
| `friends` / `friend_requests` | implicit DENY | — | — | 🔴 BROKEN → Phase 6 / #33 |
| `search` (`users`) | read signed-in | — | **reads ALL users, all colleges** | ⚠️ cross-college exposure → Phase 5 / #32 |
| `events` | read true | no collegeId | **no reader anywhere in lib** | ⚠️ global + write-only → Phase 9 / #36 |

## Gaps not yet closed by the rule set

1. **Feed is global.** `posts` are read-true and the feed query
   (`feed_screen.dart:138`) asks for *all* posts with no college filter; the
   post writer (`add_post_screen.dart`) stores no collegeId. To isolate the
   campus feed we must (a) stamp `collegeId` on post writes, (b) query
   `where('collegeId', isEqualTo: mine)`, and (c) bind the read rule to the
   caller's college. Strictest-first, backward compatible with existing posts
   (missing collegeId → rule denies → only new posts appear).
2. **Likes & comments firewalled.** Both live under `posts/{id}/` and have no
   rule block → every write/read is denied today. Phase 4 must add explicit
   blocks (like = uid-keyed doc, comment = owner-write + restricted read),
   otherwise the feed UI actions silently fail.
3. **Moments stamped but read globally.** Writer derives collegeId
   (moment_camera_screen.dart:156) but the Moments tab orders by `expiresAt`
   with no college filter (moments_screen.dart:96). Phase 8 should scope the
   query to `collegeId == user.collegeId` and tighten the read rule.
4. **1:1 chat, club chats, friends, friend requests all implicit-deny.**
   These collections have no rules → the corresponding screens can never
   complete a Firestore call. Phase 6 (#33) / Phase 7 (#34) must author
   explicit contracts (member-based reads, owner writes) tuned to each screen.
5. **Search exposes all users.** search_screen streams every `users` doc and
   shows cross-college profiles. Phase 5 (#32) should scope to the caller's
   college (reading users is signed-in-only today, but span is global).
6. **Events are write-only and global.** No screen reads `events`; no collegeId
   on the doc. Phase 9 (#36) wires a list and stamps college.

## Verified closing summary (this session)

- anon_chats rules: 18/18 emulator cases green (isolation, TTL, identity,
  immutability, room create).
- club-request contract: 27/27 emulator cases green (notifications recipient
  contract, club_requests lifecycle, admin bootstrap, members).
- `notifications` composite index added to `firestore.indexes.json` (the
  toUid+createdAt query needs it in production).