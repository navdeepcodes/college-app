# Phase 13 — Dependency review + dead-dependency cleanup

**Date:** 2026-09-13
**Commit:** see `git log` (`phase13-dependency-review`)
**Constraint compliance:** No upgrades performed. This is a *removal* of verified-dead
dependencies (review/cleanup action), consistent with constraint 3 ("no indiscriminate
upgrades") — nothing was bumped, nothing in-constraint was left behind.

## Audit result

`flutter pub outdated` reports every direct dependency at `*` (max-constrained), i.e.
there are no in-constraint updates available. Major-version bumps (firebase_core→4,
firebase_auth→6, cloud_firestore→6, google_sign_in→7, supabase_flutter→3, image_picker→2,
flutter_lints→6, cupertino_icons→2) remain deferred — they are the previously-documented
**High-tier** upgrades and were deliberately NOT executed in this phase. Rationale:
breaking upgrades across the entire Firebase + Flutter stack mid-sprint contradict the
"no dependency upgrades / no giant refactor / no rule weakening" constraints and would
not land cleanly without a full device-test pass.

## Findings

| Dependency | Direct dep? | In-constraint update | Imported anywhere? | Defect |
|---|---|---|---|---|
| firebase_core ^3.6.0 | ✔ | none | ✔ (all) | — |
| firebase_auth ^5.3.0 | ✔ | none | ✔ | — |
| cloud_firestore ^5.5.0 | ✔ | none | ✔ | — |
| google_sign_in ^6.2.1 | ✔ | none | ✔ | — |
| supabase_flutter ^2.5.0 | ✔ | none | ✔ (storage) | — |
| image_picker ^1.1.2 | ✔ | none | ✔ (5 files) | — |
| cupertino_icons ^1.0.6 | ✔ | none | ✔ | — |
| camera ^0.11.0+2 | ✔ | none | **✘ zero imports** | DEAD |
| video_player ^2.8.1 | ✔ | none | **✘ zero imports** | DEAD |
| path_provider ^2.1.4 | ✔ | none | **✘ zero imports** | DEAD |
| firebase_messaging ^15.0.0 | ✔ | none | **✘ zero imports** | DEAD |

### Dead-dependency analysis

A full-tree `import 'package:<dep>'` scan of `lib/` and `test/` found **no references** to
`camera`, `video_player`, `path_provider`, or `firebase_messaging`:

- **camera, video_player, path_provider** — survivors of the deleted Moments feature
  (`lib/moments/`). Nothing renders media or writes to app documents anymore.
- **firebase_messaging** — never initialized (no `FirebaseMessaging.instance.onTokenRefresh…`
  anywhere, no `firebase_options.dart` messaging options).

Removing them also pruned ~30 transitive packages (camerax, path `/` dart, `app_links`,
`record_use`, `hooks`, `code_assets`, `desktop_webview_auth`-adjacent messaging deps, etc.)
and, critically, **removed the native plugin registrations** for all four — build surface
shrinks with zero behavioural change.

## Verification (all green)

- `flutter pub get` — 30 dependencies removed from the lockfile; GeneratedPluginRegistrant
  (Android + iOS) rebuilt, **0 references** to camera/video_player/path_provider/messaging.
- `flutter analyze` — **No issues found**.
- `flutter test` — full suite passes (32 tests).
- `firestore.rules` untouched this phase → security contract unchanged (149 rules tests still
  the floor from Phases 10/11; re-run as part of Phase 14 gates).

## Notes / deferred

- Firebase/Flutter major-tier upgrades remain **High-tier, not executed** — safest done in a
  dedicated working session with a physical-device smoke test (analogous to `phase5`).
- `docs/phase5-dependency-modernization-audit.md` and `docs/phase4-moments-decision.md` are
  **historical**; the Moments stack and camera/video/path_provider deps are gone.