# Phase 2 — Security Contract Audit: Client ↔ Firestore Rules

**Date:** 2026-09-12 (autonomous recovery, Phase 2)
**Scope:** Every Firestore collection the client touches vs. the rules in `firestore.rules`.
**Method:** Read every `FirebaseFirestore.instance…` call site in `lib/` and the whole rules file; classify each against the rules engine semantics (no-`match` → implicit **deny**; Firestore query rules evaluate at the matched path; `set(merge)` on an existing doc counts as `update`).
**Status:** Analysis + proposed rules contract only. **No rules were modified** (standing constraint — only audit here). No data touched.

---

## 1. Rules currently matched

The deployed contract (`firestore.rules`) has `match` blocks for exactly:
`users`, `posts`, `events`, `clubs` (+ `clubs/posts`), `moments`, `anon_chats` (+ `anon_chats/messages`).

Every other collection the app writes or reads has **no match block → implicit DENY**.

---

## 2. Operation × Rule matrix

Legend — ✓ works under rules · ✗ denied by rules · ⚠ partially works / accidental allow.

| Collection | Client operation (evidence) | Rule | Verdict |
|---|---|---|---|
| **users** | Read doc/get + doc stream (feed header, profile, member tiles, comment tiles, chat peer, friends) | `read if isSignedIn()` | ✓ |
| | Create owner (`signup_screen.dart:80` set merge) | `create if isSignedIn && isOwner` | ✓ |
| | Update own (`profile_setup` set-merge line 156, `edit_profile:69`, `notification_service:31,42`, `anon_chat` batch `lastAnonMessage`) | `update if isSignedIn && isOwner` | ✓ |
| | Update **other** user (`friend_service.dart:45-53` increments `friendsCount` on both parties) | `update if isOwner` | ✗ — but `FriendService.acceptRequest` has **no callers** (dead), so not exercised by live UI today |
| **posts** | Read all (feed `feed_screen:170` stream) / read by user (`user_posts_grid:21`) | `read if true` | ✓ |
| | Create own (`add_post_screen:54` set with `userId: uid`) | `create if userId==auth.uid` | ✓ |
| | Update own (`post_card` delete) | `update/delete if userId==auth.uid` | ✓ (widget dead in UI — see §4) |
| | Update **likesCount on others' posts** (`feed_screen:147-164` txn, `post_card:123`) | `update if resource.userId==auth.uid` | ✗ — the actor is the commenter/liker, not the post author |
| | Update **commentsCount on others' posts** (`comments_screen:34`) | same as above | ✗ |
| **posts/likes** | Read own like state (`feed_screen:207-213` stream, `like_service` — dead) | **no match** | ✗ |
| | Set/Delete like (`feed_screen:150/156`, `post_card` txn) | **no match** | ✗ |
| **posts/comments** | Read list (`comments_screen:59` stream) | **no match** | ✗ |
| | Create (`comments_screen:28` add) | **no match** | ✗ |
| **events** | Read all / by club (`club_events_screen:24`, feed events) | `read if true` | ✓ |
| | Create via feed (`create_event_screen:92` set with `createdBy: uid`) | `create if createdBy==auth.uid` | ✓ |
| | Create via club screen (`club_events_screen:106` add — **no `createdBy` field**) | `create if createdBy==auth.uid` | ✗ — `undefined == uid` is false |
| | Delete (`event_card:111` delete) | `update/delete if createdBy==auth.uid` | ⚠ creator can delete own; club-created events (no `createdBy`) or another admin's events **cannot** |
| **clubs** | Read (explore `clubs_screen:196`, cards, profile) | `read if true` | ✓ |
| | Create via approval (`admin_club_requests_screen:125` add with `admins:[ownerUid]`) | `create if request.resource.data.admins == [auth.uid]` | ✗ — the approver's uid ≠ ownerUid |
| | Update by admin (`club_join` approve `membersCount` increment, `club_members_screen:212` decrement — both as part of batches) | `update if resource.admins.hasAny(uid)` | ⚠ allowed in isolation for admins, but the enclosing batch touches denied collections → whole batch fails |
| **clubs/posts** | (no client writes) | read true / member create | n/a — dead rule, no client use |
| **club_members** | Read stream where clubId (`club_members_screen:26`, `clubs_screen:159` your-clubs), read doc stream (`club_profile:175`, `club_admin_dashboard:37`) | **no match** | ✗ |
| | Create on approve (`club_join_requests_screen:205` set `${clubId}_$userId`, `admin_club_requests_screen:138` set) | **no match** | ✗ |
| | Update role / delete (`club_members_screen:192,205`) | **no match** | ✗ |
| **club_join_requests** | Add (join request: `club_profile_screen:184`) | **no match** | ✗ |
| | Stream pending (`club_join_requests_screen:23`) | **no match** | ✗ |
| | Delete (reject `:232`) | **no match** | ✗ |
| **club_requests** | Add (`create_club_screen:66`) | **no match** | ✗ |
| | Stream pending (`admin_club_requests_screen:15`) | **no match** | ✗ |
| | Update status (`admin_club_requests_screen:146,158`) | **no match** | ✗ |
| **notifications** | Add (`create_club_screen:77` club_request alert) | **no match** | ✗ |
| | Stream where toUid (`notifications_screen:39`) | **no match** | ✗ |
| | Delete (`notifications_screen:140,162`) | **no match** | ✗ |
| **friends** | Stream where members arrayContains (`friends_list:21`, `start_conversation:20`, `profile_screen:72`) | **no match** | ✗ |
| | Add/set (`notifications_screen:154` add, `friend_request_tile:70` set) | **no match** | ✗ |
| **friend_requests** | Add (`friend_service:21` sendRequest — live via two FriendButtons) | **no match** | ✗ |
| | Query dedupe (`friend_service:13`) | **no match** | ✗ |
| | Update/Delete on accept (`friend_service:57`, `friend_request_tile:61`) | **no match** | ✗ |
| **chats** (1:1) | Get/set chat doc (`chat_screen:41-50` ensure exists) | **no match** | ✗ |
| | List stream members arrayContains (`chats_list:38`, `chats_screen:18`) | **no match** | ✗ |
| **chats/messages** | Add (`chat_screen:89`) | **no match** | ✗ |
| | Stream orderBy createdAt (`chat_screen:137`) | **no match** | ✗ |
| | Status updates delivered/seen (`chat_screen:63,77`) | **no match** | ✗ |
| **club_chats** + /messages | Ensure doc, add, stream (`club_chat_screen:43,62,92`) | **no match** | ✗ |
| **anon_chats** (parent) | (never read by client — college chat only touches `/messages`) | member-gated read (dormant) | n/a — rule never evaluated |
| **anon_chats/messages** | Read unexpired (`college_anon_chat_screen:160` stream + client TTL filter) | `read if expiresAt > now` | ✓ (works) |
| | Create (`:76-90` batch set with `expiresAt = now+90s`) | `create if expiresAt <= now+90s` | ✓ (works) |
| | — but rule **does not check** sender ⊆ members, college, or `userId == auth.uid` | — | ⚠ accidental allow (see §4) |
| **anon_groups** | Add (`create_anon_group_screen:31` — dead screen, no importers) | **no match** | ✗ (and dead) |
| **moments** | Read stream (`moments_screen:96`, `my_moments:84`) | `read if true` | ✓ |
| | Create (`moment_camera_screen:168` add with `userId`, `collegeId`, `expiresAt` 3h) | `create if userId==auth.uid` | ✓ |
| | Delete own (`my_moments:12`) | `delete if userId==auth.uid` | ✓ |
| | Report — update `reportsCount` on **someone else's** moment (`moments_screen:224`) | `update if userId==auth.uid` | ✗ → report flow always fails (surfaces misleading "offline" snackbar) |
| | Reactions (`moments_screen` `_triggerReaction`) | — | n/a — **UI-only, never persisted** |

---

## 3. Failing operations — ranked

1. **Entire club subsystem is read/write-denied**
   `club_members`, `club_join_requests`, `club_requests` all have no match → no one can request to join, approve, list members, promote/remove, create a club (creation depends on `club_requests`), or see "Your Clubs". Club **profile** rendering works (reads `clubs`), but membership gating dead. Severity: full feature outage. Evidence in §2.

2. **All social-graph features denied**
   `friends` + `friend_requests` have no match. "Add Friend" (`FriendButton` → `FriendService.sendRequest`) always fails; friends lists and `isFriend` computations never return data; accept flows fail. `firestore.rules` has no `friends`/`friend_requests` block at all.

3. **1:1 chat and club chat fully denied**
   `chats`, `chats/messages`, `club_chats`, `club_chats/messages` have no match. Every message add/read/status-update fails.

4. **Likes & comments denied (and their counters require authorless updates)**
   No `posts/likes`/`posts/comments` blocks, so like reads/sets and comment reads/adds are denied. Independently, even if those subcollections were opened, the `posts` `likesCount`/`commentsCount` increments are executed by non-authors and fail the `posts.update` owner check — the same rule also breaks the feed's inline like-txn. Two independent blockers stacking.

5. **Notifications denied + structurally unreachable**
   No `notifications` block → add/stream/delete denied. Separate product bug (not rules): `create_club_screen:77` writes a notification with **no `toUid`**, so even if rules allowed it, the `notifications_screen` query `where('toUid', ==uid)` would never return it; and `type='friend_request'` is **never produced** anywhere, so that tile can never render.

6. **Event creation from the club screen denied**
   `club_events_screen:106` adds an event without `createdBy` → fails the `createdBy==auth.uid` rule. Delete of club-created events also impossible.

7. **Moments report flow always fails**
   `moments_screen:224` increments `reportsCount` on any moment; rule only allows the author to update. Moderation-by-reports is dead, and the catch block shows a *false* "offline" message.

8. **Club promotion/removal by non-author & friend accept counters** — denied; the friend-accept counter path is dead code today.

9. **CK. minors:** `chats` list needs composite index (`members` arrayContains + `lastMessageAt` order); `notifications` needs `toUid+createdAt`; `club_join_requests` needs `clubId+status` (orderBy was removed as a workaround); `events` needs `clubId+createdAt`; `moments`/`my_moments` reads rely on single-field indexes only for the pure `orderBy` case. Current `firestore.indexes.json` configures `club_requests`, a **nonexistent** `college_anon_posts` collection, and an **obsolete** `moments.college` index.

---

## 4. Operations the rules accidentally allow

These are *not* denies — they are opens wider than the product intent.

1. **Public reads of authored content (`read if true`):** `posts`, `moments`, `events`, `clubs`. Any unauthenticated / non-college user (even an anonymous Firebase user) can read all posts, moments, events, clubs. No college-partition enforced — the feed (`feed_screen:170` streams every post, no filter) and moments feed (`moments_screen:96`, no `collegeId` filter) cross colleges by design deficit.

2. **Anon message forge-ability:**
   - `create` on `anon_chats/messages` validates **only** `expiresAt` timing — not that `userId == request.auth.uid`, not that the sender is in `members`, not the college. Any signed-in user can write a message into any chat, impersonating any `anonId`/`userId` string.
   - `read` on `anon_chats/messages` grants any signed-in user every unexpired message of **every** anon chat — college isolation holds only through the `college_<id>` chatId naming, not through rules. (The parent `anon_chats` member gate is never evaluated because the client never reads the parent doc.)

3. **posts create** requires only `userId==auth.uid` — no requirement that the account completed profile setup or belongs to the claimed college; posts carry no `collegeId` and the feed doesn't filter by it, so any signed-in user can post to the global feed.

4. **moments create** validates `userId` only → user can self-assert any `anonId` and any `collegeId`; combined with public read, cross-college impersonation of campus anonymity is possible.

5. **clubs create** `admins == [auth.uid]` is trivially self-satisfiable — any signed-in user can found a club claiming sole admin. (Not client-exercised today — club creation only exists through the denied `club_requests` flow.)

6. **users create/update** are owner-gated but validate nothing about shape (no college-email check server-side; the email-domain check lives only in the signup **UI**).

---

## 5. Data-shape inconsistencies surfaced (not rules, but feed the rules design)

- **`friends` has three incompatible shapes**: `{members:[a,b]}` (`friend_service:40`, `notifications_screen:155`), `{uid:fromUid}` at doc id `$fromUid` (`friend_request_tile:68-72`). The queries require `members` arrayContains; the `{uid}` doc is invisible to them.
- **`events` has two shapes**: feed events carry `createdBy`; club events don't.
- **`notifications` missing `toUid`** in the only writer, and no writer ever emits `type:'friend_request'`.
- **`moments` reactivity is fake**: reactions render from a `reactions` map that nothing ever writes.

---

## 6. Proposed rules contract (for approval — NOT deployed)

> Standing constraint: **do not change rules inside Phase 2**, and do not *weaken* rules to make the UI work. The proposed contract below is additive/­strict (each open extends the current deny to cover the collection's real, intended shape), guarded to the app's actual invariants. Nothing here lifts a restriction that the product expects; accidental allows are closed, not kept.

```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() { return request.auth != null; }
    function isCollege() {
      // user doc is REQUIRED to be readable when this executes (rules read is allowed)
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.collegeId != null;
    }

    // ---------- users ----------
    match /users/{userId} {
      allow read: if signedIn();
      allow create, update: if signedIn() && request.auth.uid == userId
        && request.resource.data.uid == request.auth.uid;
      allow delete: if false;
    }

    // ---------- posts + interactions ----------
    match /posts/{postId} {
      allow read: if signedIn() && isCollege();          // close §4.1
      allow create: if signedIn() && isCollege()
        && request.resource.data.userId == request.auth.uid;
      allow update, delete: if signedIn()
        && (resource.data.userId == request.auth.uid
            || (request.resource.data.diff(resource.data).affectedKeys()
                  .hasOnly(['likesCount','commentsCount'])));  // counters only — matches client txn at feed_screen.dart:152, comments_screen.dart:34
      // Likes: the doc id IS the liking user's uid (feed_screen.dart:145).
      match /likes/{likeId} {
        allow read: if signedIn();
        allow create, delete: if signedIn() && likeId == request.auth.uid;
      }
      match /comments/{commentId} {
        allow read: if signedIn();
        allow create: if signedIn() && request.resource.data.userId == request.auth.uid;
        allow update, delete: if false;
      }
    }

    // ---------- events ----------
    match /events/{eventId} {
      allow read: if signedIn() && isCollege();
      allow create: if signedIn() && request.resource.data.createdBy == request.auth.uid;
      allow update, delete: if signedIn() && resource.data.createdBy == request.auth.uid;
      // Client fix required too: club_events_screen must set createdBy (see report §7).
    }

    // ---------- clubs ----------
    match /clubs/{clubId} {
      allow read: if signedIn() && isCollege();
      allow create: if signedIn() && request.resource.data.admins.hasAll([request.auth.uid]);
      allow update, delete: if signedIn() && resource.data.admins.hasAny([request.auth.uid]);
      match /posts/{postId} {
        allow read: if signedIn() && isCollege();
        allow create: if signedIn() && get(..).data.members.hasAny([request.auth.uid]);
        allow update, delete: if signedIn() && get(..).data.admins.hasAny([request.auth.uid]);
      }
    }

    // ---------- club membership + requests ----------
    match /club_members/{docId} {
      allow read: if signedIn();
      // self-join OR a club admin approving (approve writes doc `${clubId}_$userId`, role 'member')
      allow create: if signedIn() && (
          request.resource.data.userId == request.auth.uid
          || get(/databases/$(database)/documents/clubs/$(request.resource.data.clubId))
               .data.admins.hasAny([request.auth.uid]));
      allow update: if signedIn()
        && get(/databases/$(database)/documents/clubs/$(resource.data.clubId))
             .data.admins.hasAny([request.auth.uid]);
      allow delete: if signedIn()
        && (resource.data.userId == request.auth.uid
            || get(/databases/$(database)/documents/clubs/$(resource.data.clubId))
                 .data.admins.hasAny([request.auth.uid]));
    }

    match /club_join_requests/{reqId} {
      allow read: if signedIn();
      allow create: if signedIn()
        && request.resource.data.userId == request.auth.uid
        && request.resource.data.status == 'pending';
      allow update, delete: if false;   // admin acts on club_requests, not via this path
      // NOTE: approve/reject currently live in the client (club_join_requests_screen) —
      // move to a Cloud Function or grant admin gated by club doc, per §7.
    }

    match /club_requests/{reqId} {
      allow read: if signedIn();
      allow create: if signedIn() && request.resource.data.ownerUid == request.auth.uid;
      allow update, delete: if false;  // approval should be admin-only — candidate for a CFN
    }

    // ---------- notifications ----------
    match /notifications/{nid} {
      allow read: if signedIn() && resource.data.toUid == request.auth.uid;
      allow create: if signedIn() && request.resource.data.toUid == request.auth.uid; // before CFN
      allow update, delete: if signedIn() && resource.data.toUid == request.auth.uid;
    }

    // ---------- friends ----------
    match /friends/{fid} {
      allow read: if signedIn() && resource.data.members.hasAny([request.auth.uid]);
      allow create: if signedIn()
        && request.resource.data.members.hasAny([request.auth.uid]);
      allow update, delete: if false;
    }

    // ---------- 1:1 + club chat ----------
    match /chats/{chatId} {
      allow read: if signedIn() && resource.data.members.hasAny([request.auth.uid]);
      allow create, update: if signedIn() && resource.data.members.hasAny([request.auth.uid])
        && request.resource.data.members.hasAny([request.auth.uid]);
      allow delete: if false;
      match /messages/{mId} {
        allow read: if signedIn()
          && get(/databases/$(database)/documents/chats/$(chatId))
               .data.members.hasAny([request.auth.uid]);
        allow create: if signedIn()
          && get(/databases/$(database)/documents/chats/$(chatId))
               .data.members.hasAny([request.auth.uid])
          && request.resource.data.fromUid == request.auth.uid;
        allow update, delete: if false;
        // member mutation is client-side only (chat members never change after create).
      }
    }

    match /club_chats/{clubChatId} {
      allow read: if signedIn() && get(/databases/$(database)/documents/clubs/$(clubChatId))
        .data.members.hasAny([request.auth.uid]);
      allow create, update: if signedIn() && get(..).data.members.hasAny([request.auth.uid]);
      allow delete: if false;
      match /messages/{mId} {
        allow read: if signedIn() && get(..).data.members.hasAny([request.auth.uid]);
        allow create: if signedIn() && get(..).data.members.hasAny([request.auth.uid])
          && request.resource.data.userId == request.auth.uid;
        allow update, delete: if false;
      }
    }

    // ---------- anon (close the forge, keep TTL) ----------
    match /anon_chats/{chatId} {
      allow read: if signedIn() && (resource.data.members.hasAny([request.auth.uid])
        || chatId startsWith 'college_');   // college chats: legitimated by chatId name
      allow create: if signedIn() && request.resource.data.createdBy == request.auth.uid;
      allow update: if signedIn() && resource.data.members.hasAny([request.auth.uid]);
      allow delete: if false;
      match /messages/{messageId} {
        allow read: if signedIn()
          && resource.data.expiresAt > request.time;
        allow create: if signedIn()
          && request.resource.data.userId == request.auth.uid        // stops impersonation §4.2
          && request.resource.data.expiresAt <= request.time + duration.value(90, 's');
        allow update, delete: if false;
      }
    }

    // ---------- moments ----------
    match /moments/{momentId} {
      allow read: if signedIn() && isCollege();
      allow create: if signedIn() && request.resource.data.userId == request.auth.uid;
      allow update: if signedIn()
        && (resource.data.userId == request.auth.uid
            || request.resource.data.diff(resource.data).affectedKeys()
                 .hasOnly(['reportsCount','isHidden']));
      allow delete: if signedIn() && resource.data.userId == request.auth.uid;
      // collegeId self-assertion (§4.4) closes only via server-side check — out of rules' reach.
    }
  }
}
```

---

## 7. What is required *alongside* the rules (client/backend, not rules-only)

The rules alone are not sufficient for a few cells; these are Phase 6/coordinated items, listed so nobody deploys a half-fix:

- `club_join_requests` approve/reject and `club_requests` approve live in the **client** but require club-admin gating that depends on a club doc lookup mid-batch; cleanest is a **Cloud Function** (`onCreate` for club requests → approve path, or callable) — otherwise rules need an admin lookup here too.
- `club_events_screen` must set `createdBy` (currently omitted) — a client fix that the proposed `events` rule depends on.
- `notifications_screen` writer must set `toUid`; friend-request path must emit a notification.
- `college_anon_posts`/`moments.college` indexes in `firestore.indexes.json` are stale (collection doesn't exist; field renamed). Real indexes are listed in §3.9.

---

## 8. Explicitly NOT done (constraints honored)

- No `firestore.rules` / `storage.rules` files were modified.
- No Firestore data was touched, no emulator runs, no deployment.
- No behavior invented: each proposed open corresponds to a call site that exists today.
- No security rule *weakened* — every proposed `allow` is narrower than `if true` and gated on existing fields.
- Supabase service_role key: untouched (user decision "c").

## 9. Severity summary for the final report

| # | Finding | Impact |
|---|---|---|
| S1 | Clubs subsystem (members/join/requests) denies everything | Feature fully broken |
| S2 | Friends + friend_requests deny everything | Add-friend broken |
| S3 | Chats + club_chats deny everything | All messaging broken |
| S4 | Likes/comments denied (#9) + non-author counter updates denied | Feed interactivity broken |
| S5 | Notifications denied + never routed to receiver | Inbox empty |
| S6 | Club-event creation denied (missing createdBy) | Event creation half broken |
| S7 | Moments report moderation dead | Trust & safety broken |
| S8 | Public reads + anon forge-ability + no college partition | Isolation & impersonation gaps |