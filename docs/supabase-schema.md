# TrueKinn — Supabase Schema Reference

Applied via `supabase/migrations/20260914000001_initial_schema.sql` (tables/functions/triggers) and `20260914000002_rls_policies.sql` (RLS). Live on the "ReServe dev" project (ref `nczagxcixactkskqhjll`) as of this session. Firebase collection → table mapping, full column/constraint reference, and the reasoning behind every relational departure from the Firestore document shape.

## Mapping

| Firestore | Postgres | Notes |
|---|---|---|
| `users/{uid}` | `profiles` | `id` is a FK to `auth.users(id)`, not a duplicated `uid` field |
| `posts/{id}` | `posts` | |
| `posts/{id}/likes/{uid}` | `post_likes` | `UNIQUE(post_id, user_id)` replaces the uid-keyed-doc trick |
| `posts/{id}/comments/{id}` | `comments` | |
| `friend_requests/{id}` | `friend_requests` | partial unique index prevents duplicate pending requests |
| `friends/{sortedPairId}` | `friendships` | `CHECK(user_a < user_b)` replaces the client-computed sorted ID |
| `chats/{sortedPairId}` | `conversations` | same technique |
| `chats/{id}/messages/{id}` | `messages` | |
| `clubs/{id}` | `clubs` | `admins` array dropped — derived from `club_members.role` |
| `club_members/{clubId_uid}` | `club_members` | `UNIQUE(club_id, user_id)` |
| `club_join_requests/{id}` | `club_join_requests` | partial unique index on pending |
| `club_requests/{id}` | `club_requests` | (club-creation request, distinct from join request) |
| `club_chats/{clubId}` (parent doc) | *(none — not needed)* | see schema-design note below |
| `club_chats/{clubId}/messages/{id}` | `club_messages` | plain FK to `clubs.id`, no parent-row prerequisite |
| `events/{id}` | `events` | |
| `notifications/{id}` | `notifications` | `request_id` intentionally has no FK — polymorphic (points at either `club_requests` or `friend_requests` depending on `type`) |
| `anon_chats/{collegeRoom}` | `anon_rooms` | `college_id` IS the primary key — the room's identity always was its college |
| `anon_chats/{room}/messages/{id}` | `anon_messages` | |
| `moments/{id}` | `moments` | kept for parity; product stays disabled (`kMomentsEnabled = false`, untouched) |

18 Firestore collections → 18 Postgres tables. Nothing dropped, nothing invented beyond what the reference implementation already modeled — confirmed via live introspection (`select table_name from information_schema.tables where table_schema='public'`).

## Why no parent-doc table for club chats

Firestore's `club_chats/{clubId}` was a real document that had to exist before its `messages` subcollection was reachable at all — its total absence (no rule block at all, a bug fixed in Phase 18 of the Firebase hardening work) meant every club's group chat was permanently stuck loading for every user. A relational foreign key (`club_messages.club_id references clubs(id)`) has no equivalent prerequisite: a row either references a valid club or the insert fails a constraint, with no intermediate "parent document doesn't exist yet" state to get wrong. This is the single clearest example of a bug class the relational model makes structurally impossible rather than merely well-guarded.

## Why the "resource.data dereference on a nonexistent document throws" bug class cannot recur

Three separate Firestore rules bugs this project hit (`users.read` breaking every signup, Phase 20; `club_members.read` breaking every non-member's first club view, Phase 21; `chats`/`friends`, defended client-side rather than fixed at the rules layer) shared one root cause: a security rule dereferencing `resource.data` (or a `get(...).data` field) on a document that legitimately doesn't exist yet throws `permission-denied` instead of gracefully evaluating to a deny. In SQL, `select college_id from profiles where id = auth.uid()` against a nonexistent row returns an **empty result set**, not an error — and `x = NULL` is never `TRUE` in a `WHERE`/RLS predicate, so a missing row reads as a safe, silent deny by construction. No equivalent bug class exists to sweep for here; this was confirmed, not merely assumed, by the live scenario test's step 5d (a user's own not-yet-created `club_members` row reads back as an empty array, never an error).

## Functions

| Function | Purpose | Security |
|---|---|---|
| `college_id_from_email(text)` | mirrors `collegeIdFromEmail()` | INVOKER (pure, no table access) |
| `current_college_id()` | mirrors `userCollege()` | **DEFINER** (breaks self-referential RLS recursion — see migration-plan Phase 3) |
| `is_platform_admin()` | mirrors `isAdmin()` | **DEFINER** |
| `is_club_member(uuid)` | mirrors `isClubMember()` | **DEFINER** |
| `is_club_admin(uuid)` | mirrors `admins.hasAny([uid])` checks | **DEFINER** |
| `bump_post_likes_count()` (trigger) | atomic counter | **DEFINER** (updates a row the acting user doesn't own) |
| `bump_post_comments_count()` (trigger) | atomic counter | **DEFINER** |
| `bump_friends_count()` (trigger) | atomic counter | **DEFINER** |
| `bump_club_members_count()` (trigger) | atomic counter | **DEFINER** |
| `bump_conversation_last_message()` (trigger) | footer update | INVOKER — deliberately not DEFINER; the sender is always a participant, so no widening was needed (see migration-plan Phase 3 for the reasoning, not just the conclusion) |
| `enforce_college_id_on_insert()` / `enforce_profile_immutability()` (triggers) | mirror the `users.create`/`users.update` rules | INVOKER (only inspects `NEW`/`OLD`, no table access) |
| `enforce_moments_update_columns()` (trigger) | mirrors the `posts.update` non-owner-counter-only carve-out, applied to `moments` where the original Firestore rule had NO such carve-out (a real bug — see security-model doc) | INVOKER |

## Known, deliberate gaps (not inferred, not guessed)

- **`clubs` has no DELETE policy.** The reference Firestore rule (`admins.hasAny(...)`) would have technically allowed it, but no UI path in the current app ever calls it (blueprint finding, category G — missing). Adding a delete policy is a product decision (what happens to `club_members`/`club_messages` on club deletion — cascade? soft-delete?) this migration is not positioned to invent. Left absent; documented here per the mission's own "stop at this boundary rather than guessing" instruction.
- **`reports` has no table.** The migration brief mentions "reports" as an existing feature; the actual current implementation has no such collection — the closest analogue is `moments.reports_count`, a field on the moment itself, not a separate audit-trail table. No fictitious `reports` table was invented to match the brief's assumption; this finding is called out explicitly rather than silently building something that doesn't reflect the reference implementation.
