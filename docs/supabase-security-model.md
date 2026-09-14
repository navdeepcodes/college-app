# TrueKinn — Supabase RLS Security Model

Every Firestore `match` block's `allow` clauses, mapped to its Postgres RLS `policy` equivalent in `supabase/migrations/20260914000002_rls_policies.sql`. This is the direct successor to `firestore.rules` (582 lines, 20 match blocks) — read that file's own comments alongside this table where more context is needed; nothing here contradicts it without an explicit note.

| Firestore block | Postgres table | Mapping | Verified live? |
|---|---|---|---|
| `users/{userId}` | `profiles` | own row always readable (no existence precondition — see schema doc); same-college readable; admin reads all; create=own row only + college_id/email match (trigger); update=own row, immutable college_id/anon_id (trigger); delete=never | ✅ scenario steps 1a–1e |
| `posts/{postId}` | `posts` | college-scoped read; owner-or-college-matching create; owner-only update/delete (no counter carve-out needed — counters are trigger-maintained, not client-writable at all) | ✅ steps 2a–2c |
| `.../likes/{likeId}` | `post_likes` | read/create/delete gated on the parent post's `college_id` matching; `UNIQUE(post_id,user_id)` replaces the uid-keyed-doc convention | ✅ steps 2d–2f |
| `.../comments/{commentId}` | `comments` | same shape as likes, plus non-blank text check | *(not separately exercised this pass — covered by the posts_update/likes precedent; see status doc)* |
| `events/{eventId}` | `events` | college-scoped read/create/update/delete, owner-checked | ✅ steps 7a–7c |
| `club_requests/{requestId}` | `club_requests` | owner-or-admin read; owner-only pending create; admin-only update/delete | ✅ step 5a |
| `notifications/{notificationId}` | `notifications` | recipient-only read; sender-must-not-be-recipient create; recipient-only update/delete | ✅ steps 8a–8c |
| `club_members/{memberId}` | `club_members` | own-row-or-club-admin-or-platform-admin read; club-admin-or-platform-admin create/update/delete | ✅ steps 5d, 5f, 5g |
| `club_join_requests/{requestId}` | `club_join_requests` | applicant-or-admin read; applicant-only pending create; admin-only update/delete; partial unique index prevents duplicate pending requests | ✅ step 5e |
| `chats/{chatId}` | `conversations` | membership-scoped read/update; `CHECK(user_a<user_b)` replaces the client-checked sorted-pair rule | ✅ steps 4a, 4d |
| `.../messages/{messageId}` | `messages` | membership-scoped read; sender-identity-enforced create; recipient-only status update; no delete | ✅ steps 4b–4d |
| `friends/{friendId}` | `friendships` | membership-scoped read/delete; consent-checked create (source request must be pending, naming exactly these two members); no update (immutable edge) | ✅ steps 3d–3f |
| `friend_requests/{requestId}` | `friend_requests` | sender-or-recipient read/delete; sender-identity-enforced create; recipient-only status update; partial unique index prevents duplicate pending requests in either direction | ✅ steps 3a–3c, 3g |
| `club_chats/{clubId}` (parent) | *(none — see schema doc)* | n/a | n/a |
| `club_chats/{clubId}/messages` | `club_messages` | member-scoped read/create; no update/delete | ✅ steps 5h, 5i |
| `clubs/{clubId}` | `clubs` | public read; admin-only create (owner ≠ admin — closes the self-service-creation bypass Phase 18 of the Firebase work closed); club-admin-only update; **no delete policy** (documented gap, schema doc) | ✅ steps 5b, 5c |
| `clubs/{clubId}/posts` | *(not built — see status doc)* | | |
| `moments/{momentId}` | `moments` | **improved over the reference, not just ported** — see below | *(not live-tested this pass — feature stays disabled; see status doc)* |
| `anon_chats/{chatId}` | `anon_rooms` | own-college read/create only; no update/delete | ✅ steps 6a, 6b |
| `.../messages/{messageId}` | `anon_messages` | own-college + not-expired read; strict schema + TTL-bound create; no update/delete | ✅ step 6c |

## Where this version deliberately improves on the reference rather than just porting it

The mission's own instruction was to use `firestore.rules` as the *behavioral reference*, not to blindly copy a bug forward when fixing it costs nothing extra. Two such cases, both in the currently-disabled `moments` table (so neither changes anything a real user can reach today):

1. **College isolation.** The Firestore `moments.read` rule was `allow read: if true` — no `collegeId` check at all (a real finding from the prior session's production-readiness blueprint, §6d). The Postgres `moments_select` policy enforces `college_id = current_college_id()` from the start.
2. **Report flow.** The Firestore `moments.update` rule was strictly owner-only, with no carve-out for a non-owner flipping `reportsCount`/`isHidden` — meaning the in-app "Report" button was provably broken for its entire actual use case (reporting someone ELSE's content), confirmed via code read in the prior session (blueprint §6e). The Postgres version adds a trigger-enforced column restriction (`enforce_moments_update_columns`) that lets a non-owner change only `reports_count`/`is_hidden`, mirroring the same technique `posts.update` already used for its own non-owner counter carve-out.

Both fixes are inert while `kMomentsEnabled = false` — they exist so a future re-enable decision starts from a correct implementation instead of reintroducing two already-documented bugs.

## Bugs found via live testing (not visible from reading the policies alone)

Documented in full in `docs/supabase-migration-plan.md` Phase 3 and inline in `supabase/migrations/20260914000003_fix_rls_helper_recursion.sql`:

1. RLS helper self-referential recursion (`current_college_id()` and friends querying a table whose own policy calls them back) — `stack depth limit exceeded` on the first real write that exercised one.
2. Counter-maintenance triggers blocked by the target row's own `UPDATE` policy when the acting user isn't that row's owner.

Both fixed with `SECURITY DEFINER` + pinned `search_path`, applied narrowly (one trigger, `bump_conversation_last_message`, was checked and correctly left as the default, since it needed no widening — see the migration-plan's Phase 3 for why, not just the fact that it was skipped).

## What "verified live" means here

Every ✅ above corresponds to a passing step in `supabase/tests/rls_scenario_check.py`, run against the real "ReServe dev" project using real Supabase Auth accounts and real signed session JWTs from an actual password sign-in — not a local RLS emulator (Supabase has none equivalent to the Firestore Emulator Suite this project's `functions/test-rules/` tests run against) and not hand-crafted tokens. 40/40 steps passed on the final run this session. Anything without a ✅ in the table above was covered by schema/policy design and code review, following the same pattern as an already-verified sibling policy, but was not independently exercised with its own scenario step this session — see `docs/supabase-migration-status.md` for the honest accounting of what that gap means for readiness.
