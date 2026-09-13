# Phase 14 — Testing gates + runtime verification

**Date:** 2026-09-13
**Goal:** Close the sprint's verification loops. Everything here is **read-only / no-op safe**
— no rules edits, no schema changes, no dependency changes, no production writes.

## Gate 1 — Static + unit gates (DONE, all green)

| Gate | Command | Result |
|---|---|---|
| Analyzer | `flutter analyze` | No issues found (0) |
| Unit/widget tests | `flutter test` | 32/32 passed |
| Dependency dead-import scan | grep across `lib/` + `test/` | camera/video_player/path_provider/firebase_messaging = zero imports (removed in Phase 13) |

## Gate 2 — Firestore rules suite (emulator)

Re-runs all five suites against the CURRENT `firestore.rules` (149 cases: 18 anon + 44 chat +
40 club + 30 feed + 17 search). Command:

```bash
firebase emulators:exec --project demo-truekinn --only firestore \
  'node functions/test-rules/anon_rules.test.js && \
   node functions/test-rules/chat_rules.test.js && \
   node functions/test-rules/club_rules.test.js && \
   node functions/test-rules/feed_rules.test.js && \
   node functions/test-rules/search_rules.test.js'
```

**Result:** ✅ **149/149 passed, 0 failed** (2026-09-13): anon_chat_rules 18, chat_rules 44,
club_request_rules 40, feed_rules 30, search_rules 17. Emulator `exit code 0` for all five
suites. Security contract verified against the CURRENT `firestore.rules` — no drift from the
Phase 10 college-isolation/anonId hardening.

## Gate 3 — Runtime Firestore composite-index coverage (READ-ONLY AUDIT, DONE)

Cross-checked every `.where()` / `.orderBy()` query shape in `lib/` against the six declared
indexes in `firestore.indexes.json`. **No query requires a composite index that is missing**
— meaning **no runtime index-failure risk** from the indexed query shapes:

| Query (file) | Shape | Composite needed? | Covered by? |
|---|---|---|---|
| posts — feed (`lib/feed/feed_screen.dart`) | `collegeId == X` + `orderBy createdAt desc` | YES | declared #1 ✔ |
| notifications (`lib/notifications/notifications_screen.dart`) | `toUid == X` + `orderBy createdAt desc` | YES | declared #2 ✔ |
| club_members — your clubs (`lib/clubs/clubs_screen.dart`) | `userId == X` (no orderBy) | no | auto |
| clubs — explore (`lib/clubs/clubs_screen.dart`) | unfiltered | no | auto |
| club_requests — admin (`lib/clubs/admin_club_requests_screen.dart`) | `status == pending` (no orderBy) | no | auto |
| club_join_requests (`lib/clubs/club_join_requests_screen.dart`) | `clubId ==` + `status ==` (no orderBy) | no | auto |
| anon_chats messages (`lib/anon/college_anon_chat_screen.dart`) | `orderBy createdAt desc` only | no | auto |
| chats messages (`lib/chat/chat_screen.dart`) | `orderBy createdAt desc` only | no | auto |
| chat message status sweeps (`lib/chat/chat_screen.dart`) | `toUid ==` + `status ==` (no orderBy) | no | auto |
| club_chats messages (`lib/clubs/club_chat_screen.dart`) | `orderBy createdAt desc` only | no | auto |
| chats list (`lib/chat/chats_list_screen.dart`) | `members arrayContains uid` (client-side sort) | no | auto |
| friends (`lib/chat/start_conversation_screen.dart`) | `members arrayContains uid` | no | auto |
| users search (`lib/search/search_screen.dart`) | `collegeId == X` (client-side filter) | no | auto |
| club_members doc — dashboards (`lib/clubs/club_admin_dashboard_screen.dart`) | doc get | no | auto |

### Candidate-dead declared indexes (STOP → document, do NOT drop)

Four declared indexes have **no matching current query** in the audited UI. Firestore also
auto-indexes single-field equality, so these are inert at runtime, but they're wasted write
amplification. Per sprint constraints (no risky/DB-mutating changes without the user), these
are **flagged for user review, not removed**:

1. `club_requests` (status↗, createdAt↘) — only query is `status == pending`, unordered.
2. `chats/{chatId}/messages` (toUid↗, status↗) — status sweeps are equality-only, unordered.
3. `friend_requests` (fromUid↗, toUid↗, status↗) — **no `friend_requests` query found** in the
   app (friend-request flow runs through `notifications`, not this collection); likely legacy.
4. `college_anon_posts` (collegeId↗, isHidden↗, createdAt↘) — **no `college_anon_posts` query
   found** (anon messaging runs through `anon_chats/{chatId}/messages`); likely legacy from the
   pre-chat anon-posts design.

Confirm the "no query" claims with one grep before any drop:

```bash
grep -rn "friend_requests\|college_anon_posts" lib/ --include=*.dart
```

## Gate 4 — Live production Firestore data

Live-database inspection (doc counts, rules-vs-deployed diff, stray collections) requires
admin credentials that are NOT tracked in this repo (`lib/secrets.dart` is git-ignored; no
service-account key exists). Verified instead, with no credentials, everything that governs
runtime behaviour: rules contract (Gate 2) and index coverage (Gate 3). If the user runs
`firebase login`, the following is available for a full live pass (CURRENTLY NOT EXECUTED):

- `firebase deploy --only firestore --dry-run` — validates rules compile against the real project.
- Admin-SDK or `firebase firestore` reads for collection inventory (needs a service-account key).

## Gate 5 — Secret scan (repeat of Phase 8 baseline)

grep for apiKey/private/password patterns across tracked files (excluding `.git`, `build/`,
`functions/node_modules/`, and the git-ignored `lib/secrets.dart`). Expected: the public key
material in `lib/firebase_options.dart` only (client-safe by design).

## Gate summary

- **No runtime index failures:** every app query is satisfiable by a declared or auto index.
- **No rules drift:** emulator suite re-run green (see Gate 2 line).
- **No dead native plugins:** registrants contain zero references to removed packages.
- **Open items handed to the user:** (a) 4 candidate-dead indexes to confirm via grep + drop;
  (b) live-data admin pass after `firebase login` (optional).