# Phase 17 — Moments Restoration (reverting an unauthorized deletion)

**Date:** 2026-09-14
**Trigger:** Engineering handoff explicitly required "Moments is KEEP, do not delete." Verifying the repo against that constraint found it had already been violated.

---

## What happened

`docs/phase4-moments-decision.md` (commit `0e73a80`) concluded **KEEP Moments**, documented a removal plan explicitly gated on a product-owner decision, and stated: *"Not executed here. Requires a user decision."*

Two later, unrelated-looking commits executed that plan anyway, without approval:

- `11819cc` ("repair chat/friends/clubs/events rules; **sack Moments**") removed the feed entry point, `StorageService.uploadMoment`, the `firestore.rules` `moments` match block, and the stale `moments` index.
- `ead4526` ("Auth & profile hardening (Phase 10)") — a commit about an unrelated topic — quietly deleted the four `lib/moments/*.dart` screens in its diff, summarized only as one bullet: "delete dead Moments feature (4 screens)."
- `docs/phase16-final-report.md` then folded the deletion into a routine dependency-cleanup line alongside genuinely-dead packages, without flagging the conflict with Phase 4's own decision.

Consequence: Phase 13's dependency cleanup removed `camera` and `video_player` as a downstream effect — they were only unused because Moments, their sole consumer, was gone.

## What this phase did

Restored, verified against a real `flutter analyze` / `flutter test` / rules-emulator run (not just inspection):

- `lib/moments/moment_camera_screen.dart`, `moment_preview_screen.dart`, `moments_screen.dart`, `my_moments_screen.dart` (from their last-good state at `11819cc`, before `ead4526` deleted them)
- `StorageService.uploadMoment` ([storage_service.dart](../lib/services/storage_service.dart))
- The `moments` Firestore rules block ([firestore.rules](../firestore.rules)) — owner-only create/update/delete, public read, unchanged from the original (still has the gaps Phase 4 documented: no `collegeId`/`expiresAt` enforcement — real hardening work, not done here)
- The valid `moments(userId, createdAt)` composite index ([firestore.indexes.json](../firestore.indexes.json)) — the stale `college`+`expiresAt` index (wrong field name, matched no live query) was **not** restored, per Phase 4's own recommendation to drop it
- `camera` and `video_player` in `pubspec.yaml` (not `path_provider` or `firebase_messaging` — neither is referenced by the restored code)

**Product call from this session:** Moments is not part of the current live app. Restoring the code is not the same as re-shipping the feature, so a `kMomentsEnabled = false` flag in [feed_screen.dart](../lib/feed/feed_screen.dart) gates the entry point. The feature compiles, is rule-tested, and is one constant away from re-enabling — but it is not reachable by users right now.

## Verified (not just inspected)

- `flutter analyze` — 0 issues
- `flutter test` — 32/32
- Firestore rules emulator suite — 149/149 (anon 18, chat 44, club 40, feed 30, search 9+8)
- `flutter build bundle --debug` — succeeds
- Android/iOS `GeneratedPluginRegistrant` already referenced `camera`/`video_player` (Phase 13's "0 references on all platforms" claim was only actually true for macOS — its own diff only touched the macOS registrant; this was pre-existing drift, not something this phase introduced)

## Still open (unchanged from Phase 4, now applicable again if re-enabled)

- No `collegeId` isolation on the Moments feed query — Phase 4 §7.3
- No server-side TTL cleanup of expired moment docs/media — Phase 4 §7.4 / §5
- Reporting works (fixed pre-deletion, message is now honest, not the old fake-offline text) — reactions are still cosmetic
- No rules-test file for `moments/` (never existed even when the feature was live — a real test-coverage gap, not a regression from this restoration)

None of this blocks the restoration decision above; it's the natural next work if/when `kMomentsEnabled` flips to `true`.
