# Phase 11 — Moderation integration

**Status:** DONE. **Commit:** see git log for the phase commit.

## Scope

The app's content filter (`lib/moderation/text_filter.dart`, banned-word + banned-emoji
list, block‑and‑flag semantics) previously ran in **exactly one** place: the anonymous
college-room chat send path. All other free-text surfaces accepted unfiltered content.

Phase 11 integrated the **same** filter at every chat/UGC write path, using the anon-chat
pattern verbatim (filter BEFORE the write; blocked input is rejected with an
`⚠️ … blocked by filter` SnackBar and nothing is persisted; allowed text is written via
`result.cleanedText`):

| Surface | File | Gate |
|---|---|---|
| Campus feed post caption | `lib/feed/add_post_screen.dart` | before media upload + Firestore write |
| Post comment | `lib/feed/comments_screen.dart` | before `comments.add` |
| College club chat | `lib/clubs/club_chat_screen.dart` | before `club_chats…/messages.add` |
| 1:1 chat message (and list preview) | `lib/chat/chat_screen.dart` | before message + footer write |
| Anonymous room chat | `lib/anon/college_anon_chat_screen.dart` | already integrated (unchanged) |

No rules were changed and nothing was weakened (constraints 5/6/7).

## Deliberately NOT gated (documented, not invented)

Profile fields (`name`/`nickname`/`bio`), event `title`/`description`, and
club `name`/`description` text fields were **left unfiltered**:

- The blocklist contains common substrings (e.g. `cunt`, `sule`, `gaand`) that would
  false-positive on legitimate names/words, and these fields are arguably identity data,
  not chat content.
- The original implementation never gated them; applying the filter there would invent
  product behavior beyond the evidence (constraint 8).
- **Recommendation for owner sign-off:** if identity fields should be moderated, swap the
  substring `contains()` matching for whole-word boundaries before enabling.

## Known limitation (client-side only)

This is **client-side moderation** — a malicious client can bypass it by writing to
Firestore directly. The Cloud Functions runtime (Node) could re-validate text on write,
but enforcing a wordlist in Firestore rules is brittle. This is the app's existing
architecture (filter + client gate); server-side enforcement is a separate
backend/security task, not a Phase 11 goal. Rules still enforce the structural contract
(non-empty trimmed text, author identity).