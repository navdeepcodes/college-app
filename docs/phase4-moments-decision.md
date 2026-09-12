# Phase 4 — Moments Feature: Final Decision

**Status:** Decision document (PENDING human decision where flagged)
**Date:** 2026-09-12
**Scope:** Moments feature (create/feed/delete) — recommendation only. **No deletion executed; no destructive backend change.** Constraint honored: "Do NOT delete Moments automatically."

---

## 1. Executive recommendation

**KEEP Moments as a live feature** and fix it in Phase 6. Do not remove it.

Rationale, on evidence:

- Moments is the app's only **ephemeral (3h TTL), anonymous** media-sharing surface and is wired into the main product (`lib/feed/feed_screen.dart:117` mounts `MomentsScreen` as feed tab index 1).
- Its **core loop is functional**: capture/upload (`lib/moments/moment_camera_screen.dart`), community browse (`lib/moments/moments_screen.dart`), and owner delete (`lib/moments/my_moments_screen.dart:11`). This is confirmed reachable-by-code and compiles; the client write contract matches the current rules.
- Nothing in the evidence justifies removal as "production dead weight": it is imported live, has working storage writes, and a satisfiable query profile. Removing it would delete MVP surface, not dead code.
- The non-working parts (reporting, reactions) are **broken features to fix**, not reasons to delete the feature. Both are fixable with additive, non-weakening changes (Section 7).

**Gate:** If the product owner decides the anon-moment format is out of scope, use the removal plan (Section 8) — but that is a product decision, not something to infer from code.

---

## 2. Feature surface (live code)

| File | Role | Evidence |
|---|---|---|
| `lib/feed/feed_screen.dart` | mounts `MomentsScreen` as the "Moments" toggle tab | `lib/feed/feed_screen.dart:116-122` (tab index 1 → `const MomentsScreen()`) |
| `lib/moments/moments_screen.dart` | community feed; ephemeral browse; report UI; reaction burst; add-moment FAB | reads `moments` ordered by `expiresAt`, filters `isHidden`/expired client-side (`:94-112`); FAB → `MomentCameraScreen` (`:170-190`) |
| `lib/moments/moment_camera_screen.dart` | photo/video capture + inline Supabase upload + write Firestore doc | uploads to `moments` bucket (`:159-167`), writes doc with `userId, anonId, collegeId, mediaUrl, isVideo, visibility, expiresAt = now + 3h` (`:168-178`) |
| `lib/moments/moment_preview_screen.dart` | post-capture preview + visibility choice | live via `moment_camera_screen.dart:117-137` |
| `lib/moments/my_moments_screen.dart` | my moments list + delete | owner delete `:11-22`; query `where userId == uid orderBy createdAt desc` `:84-87` |

Backend contract writes for a moment document:

| Field | Written by | Enforced by rules? |
|---|---|---|
| `userId` | camera (`:169`) | yes — create requires `userId == request.auth.uid` (`firestore.rules:84-85`) |
| `anonId` | camera (`:170`) | no |
| `collegeId` | camera (`:171`) | no |
| `mediaUrl` | camera (`:172`) | no |
| `isVideo` | camera (`:173`) | no |
| `visibility` | camera (`:174`) | no — written but **never enforced or read** |
| `expiresAt` | camera (`:176-177`) | no (read query relies on client-side filter) |
| `createdAt` | camera (`:175`) | no |

---

## 3. Orphaned / reusable parts

- **`StorageService.uploadMoment` is dead method code** — `lib/services/storage_service.dart:49-58`. No callers: the only upload path is the camera's own inline `_uploadMoment` (`moment_camera_screen.dart:139-179`). Nothing imports/uses it. Candidate to remove in Phase 6 (or keep — harmless single method).
- **`collegeId` is written but unused for isolation.** The camera stores it (`moment_camera_screen.dart:171`), but the community feed does not filter by it (`moments_screen.dart:95-98` streams ALL moments). Cross-college exposure (same accidental-allow pattern as posts — see Phase 2 audit). Reusable asset if college isolation is extended to Moments.
- **`visibility` field is aspirational** — written by the preview selector, ignored by rules and by the feed. Either implement or drop the field.
- **Stale index** — `firestore.indexes.json:46-63` declares a `moments` composite on **`college`** + `expiresAt`, but writes now use **`collegeId`**. The index matches no live query. Safe to delete (Phase 8 cleanup) once no query references it.

---

## 4. MVP value assessment

**In / strong:**
- Ephemeral anonymous sharing is a differentiated behavior vs. the named-posts feed.
- Create → browse → delete core loop is code-complete and rule-compliant.
- Query profile is satisfiable by *existing* declared indexes (Section 6), so no blocked reads.

**Out / broken (fix, don't delete):**
- **Reporting is non-functional.** `moments_screen.dart:219-253` increments `reportsCount` and sets `isHidden` when ≥3 on a moment owned by another user. Rules deny it: update requires `resource.data.userId == request.auth.uid` (`firestore.rules:87-88`). Every report throws → the UI then shows **"You are offline. Report will sync later"** (`moments_screen.dart:247`), a **misleading** message that hides a permission failure. Product bug (Phase 6, high priority).
- **Reactions are cosmetic.** `_triggerReaction` (`moments_screen.dart:61-66`) only plays a local emoji burst. The `reactions` map read at `:292` and `:338-343` is never written anywhere in Live code. Counts are always 0 for new moments.
- **`isHidden` flag is only read, never set** by any working path (the setter is the broken report flow). It filters `:109` in the feed but no moment can currently reach `isHidden=true`.

---

## 5. Backend & storage lifecycle

- **Firestore `moments` collection** documents expire by `expiresAt` (3h) but are **never deleted server-side**. The only scheduled function is `cleanupExpiredAnonMessages` (`functions/index.js:8-40`) targeting `anon_chats` messages only. Expired moment docs therefore accumulate, and every `moments_screen` snapshot re-reads them before client-side filtering (`moments_screen.dart:106-112`). Growth cost: unbounded with usage.
- **Supabase `moments` storage bucket** holds every uploaded photo/video permanently. Public URLs (`getPublicUrl`) mean any object is fetchable by URL. Two ratchets to deletion (Supabase object AND Firestore doc) means a doc-deletion approach must also delete objects — or choose tombstone-vs-purge (Section 9).
- **No TTL mechanism** (Firestore TTL policy is not used; there is no policy file in repo).

---

## 6. Security posture (current rules)

Current `firestore.rules:79-89`:

```
match /moments/{momentId} {
  allow read: if true;
  allow create: if isSignedIn() && request.resource.data.userId == request.auth.uid;
  allow update, delete: if isSignedIn() && resource.data.userId == request.auth.uid;
}
```

- **Public read** for all moment documents regardless of college/anon browsing — matches the posts/events pattern (product chose a public community feed). Consistent, but note it in the cross-college context.
- **Create/update/delete are strictly owner-only** — good. The reporting bug is the *only* consequence of this strictness: there is no sanctioned path for a third party to register a report.
- The **report "fix" must not weaken this rule.** The Phase-2 stance (additive, strict rules) applies: see Section 7 options.

Composite-index status (from `firestore.indexes.json`):
- `moments.userId ASC + createdAt DESC` **exists** (`:64-82`) → `MyMomentsScreen` query (`where userId == uid orderBy createdAt desc`) is satisfiable. ✔
- `moments.college ASC + expiresAt DESC` (`:46-63`) references the **renamed field** → orphaned/stale. ✘ to delete.
- Feed query (`orderBy expiresAt` alone) needs only the auto single-field index. ✔

> Note on prior summary: "my_moments needs composite index" is **resolved** — the userId+createdAt index is declared in `firestore.indexes.json:64-82`.

---

## 7. Fix options for Phase 6 (all additive / rule-strict)

1. **Reporting that respects ownership** — additive subcollection + function:
   - Add rules: `match /moments/{momentId}/reports/{repId} { allow create: if isSignedIn(); allow read: if isOwner(new parent userId)? /* decide */ allow update, delete: if false; }`.
   - Cloud function (e.g. `onWrite` on `moments/{id}/reports`) increments `reportsCount` on the parent and sets `isHidden=true` at ≥3 — using admin SDK (already in use, `functions/index.js:4`).
   - Client: writer writes `{reportId, uid}` doc; UI shows real success/denial (remove the fake "offline" message) when function confirms.
2. **Reactions persistence** — write per-emotion docs (e.g. `moments/{id}/reactions/{uid}` with `{emoji}`) under an additive rule, and have the feed derive counts. No rule weakening; owner-only remains for the moment doc itself.
3. **College isolation (if intended)** — add `where collegeId == canonical` to the feed query; requires the existing `college` index to be replaced with `collegeId` + `expiresAt`.
4. **TTL cleanup** — a scheduled `cleanupExpiredMoments` function (same pattern as anon messages) that batch-deletes expired moment docs by `expiresAt <= now`, plus optional Supabase object deletion by URL path. Production-safe (bounded batches, `functions/index.js` already does this).

These are **recommendations for Phase 6**, not changes made here.

---

## 8. Removal plan (documented, NOT executed)

Per the standing constraint **Do NOT delete Moments automatically**, this plan exists only for a product owner decision. If authorized:

1. Remove imports/usages in `lib/feed/feed_screen.dart:117` (`MomentsScreen` tab), and delete the four `lib/moments/*.dart` screens.
2. Delete orphaned `StorageService.uploadMoment` (`lib/services/storage_service.dart:49-58`).
3. Drop the stale `college` index (`firestore.indexes.json:46-63`) and the unused `userId+createdAt` moments index (`:64-82`) if no other query needs it.
4. Backend/storage (destructive, requires explicit approval):
   - Option A (tombstone): keep docs, stop serving. Cheapest, no destructive op.
   - Option B (purge): batch-delete expired moment docs (`expiresAt <= now`) via a scheduled function, and delete Supabase objects by stored `mediaUrl` path. Bound batches (≤500/op), dry-run first in staging.
5. Rules: retire the `moments` match block.

**Not executed here.** Requires a user decision.

---

## 9. Production-safety plan

- **Reads**: `my_moments` and community feed queries are satisfiable by declared indexes; verify-deploy `firestore.indexes.json` on next deploy (the file declares them; actual deployment state is unknown to this console).
- **Writes**: camera's doc shape satisfies current create rule unconditionally.
- **No destructive backend change** was made in this phase. The only toggle suggestion above (removal) is gated on owner approval.
- **Data-growth risk** (expired docs + media) is real but non-urgent; recommend the TTL function (Section 7.4) as Phase 6 work.

---

## 10. Open questions for the product owner

1. Is cross-college moment visibility intended (like posts), or should the feed filter by `collegeId`?
2. Should reporting/reactions be implemented (Phase 6 scope), or is the anon-moment format being sunset — in which case coordinate with Section 8?
3. Is `visibility` (public/private-ish) a real requirement? If not, drop the field.

---

*Reviewed against the Phase 2 rules contract audit; no rule changes proposed or made by this phase.*