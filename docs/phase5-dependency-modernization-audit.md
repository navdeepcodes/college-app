# Phase 5 — Dependency Modernization Audit

**Status:** Audit + safe-tier upgrade executed (tests green)
**Date:** 2026-09-12
**Environment:** Flutter 3.38.5 stable (Dart 3.10.4), compileSdk 34 / minSdk 23 / targetSdk 34, AGP 8.2.2, Kotlin 1.9.24, Gradle 8.4, iOS deployment target 13.0.

**Constraint honored:** "Do not upgrade all dependencies indiscriminately." Only a scoped, low-risk tier was executed (see §3). Major upgrades are documented but not performed.

---

## 1. Dependency inventory (direct)

| Package | pubspec constraint | Resolved now | Highest in-constraint | Resolvable/latest (needs constraint edit) | Tier |
|---|---|---|---|---|---|
| `firebase_core` | `^3.6.0` | 3.15.2 | 3.15.2 (at cap) | 4.14.0 (major) | High |
| `firebase_auth` | `^5.3.0` | 5.7.0 | 5.7.0 (at cap) | 6.6.1 (major) | High |
| `cloud_firestore` | `^5.5.0` | 5.6.12 | 5.6.12 (at cap) | 6.9.0 (major) | High |
| `firebase_messaging` | `^15.0.0` | 15.2.10 | 15.2.10 (at cap) | 16.6.0 (major) | High |
| `google_sign_in` | `^6.2.1` | 6.3.0 | 6.3.0 (at cap) | 7.2.0 (major) | High |
| `supabase_flutter` | `^2.5.0` | 2.12.0 | 2.17.2 | 2.17.2 | **Safe** (via pub upgrade — at cap after) |
| `camera` | `^0.11.0+2` | 0.11.3 | 0.11.4 | 0.12.1 (major) | **Safe** (patch) / controlled for 0.12 |
| `video_player` | `^2.8.1` | 2.10.1 | 2.11.1 | 2.14.0 | **Safe** |
| `image_picker` | `^1.1.2` | 1.2.1 | 1.2.3 | 1.2.3 | **Safe** |
| `path_provider` | `^2.1.4` | 2.1.5 | 2.1.6 | 2.1.6 | **Safe** |
| `cupertino_icons` | `^1.0.6` | 1.0.8 | 1.0.9 | 1.0.9 | **Safe** |
| `flutter_lints` | `^3.0.0` | 3.0.2 | 3.0.2 (at cap) | 6.0.0 (major, dev-only) | Controlled |

Key observation: the three Firebase packages, google_sign_in and firebase_messaging are **already at their in-constraint maximums**. A normal `flutter pub upgrade` will not move them — only *editing* pubspec constraints would trigger majors. That makes the safe tier genuinely safe.

---

## 2. Tier definitions

**Safe (executed — within existing `^` constraints, patch/minor only):**
`supabase_flitter` (2.12→2.17), `camera` (patch), `video_player` (minor), `image_picker` (patch), `path_provider` (patch), `cupertino_icons` (patch), plus locked transitive bumps (supabase, storage_client, realtime_client, postgrest, camera platform plugins, app_links) that resolve with them.

**Controlled (documented, do later deliberately):**
- `google_sign_in` 6.x → 7.x: major API surface change (sign-in semantics); the app currently uses it minimally, but any change here touches auth — do only as a focused task with manual Google sign-in verification. Blocked also by iOS auth config details.
- `camera` 0.11 → 0.12 + `camera_android_camerax` 0.7: camera controller behavior ground; touch-and-test on device.
- `flutter_lints` 3.x → 6.x: dev-only; will surface many new lint infos — adopt later near Phase 7/8 when analyze noise is the focus.
- Android `compileSdk` 34 → 35/36, AGP 8.2 → 8.7/8.9: required *before* any Firebase major upgrade (newer Firebase Android artifacts want compileSdk 35+). Part of the High tier prerequisite.

**High risk (do NOT execute autonomously — needs green-light + staging verification):**
Firebase majors (`firebase_core` 4.x, `firebase_auth` 6.x, `cloud_firestore` 6.x, `firebase_messaging` 16.x). Rationale:
- Cross-package API churn (Timestamp/FieldValue/query APIs, plus breaking Android/iOS native pod/artifact moves).
- iOS deployment-target / pod alignment could re-open the GTMSessionFetcher resolution surface.
- Nothing in the app currently requires a newer Firebase than what's resolved; the entire contract (rules, functions node 18) is independent of the client SDK version.
- Per constraint "Do not upgrade all dependencies indiscriminately" — majors are deliberately out of scope until a dedicated pass.

---

## 3. Safe tier execution

Ran `flutter pub upgrade` (respects existing constraints). Resulting direct-package movement:
- `supabase_flutter 2.12.0 → 2.17.2` (largest bump in tier)
- `camera 0.11.3 → 0.11.4`, `video_player 2.10.1 → 2.11.1`, `image_picker 1.2.1 → 1.2.3`, `path_provider 2.1.5 → 2.1.6`, `cupertino_icons 1.0.8 → 1.0.9`

**Surface-check before executing:** app's Supabase calls are `Supabase.initialize()` + `storage.from(<bucket>).upload/.getPublicUrl` only (lib/main.dart:13; moment_camera_screen.dart:159-166; create_club_screen.dart:52-63; profile_setup_page.dart:29,114-122; storage_service.dart). No Supabase auth. `storage` API is stable across 2.12→2.17. Camera surface uses `availableCameras/CameraController/takePicture/startVideoRecording` (moment_camera_screen.dart:47-97) — stable.

**Gate:** analyze, test, and debug-bundle build re-run after upgrade; must stay green (see §4).

---

## 4. Post-upgrade verification

- `flutter analyze` → 0 errors (no new issues introduced by the upgrade; any new infos are lint-only and unrelated).
- `flutter test` → all pass.
- `flutter build bundle --debug` → fresh kernel_blob produced.

(Legacy `flutter pub outdated` re-run at time of writing showed all Firebase/google_sign_in still at in-constraint caps.)

---

## 5. CocoaPods / iOS notes

- `ios/Podfile.lock` currently resolves `GTMSessionFetcher 3.5.0`, `GoogleSignIn 8.0.0`, `GTMAppAuth 4.1.1` — consistent (the earlier "lock-vs-plugin conflict" is not present in the current lock).
- iOS deployment target 13.0 (pbxproj). Safe-tier Dart-only changes do not touch pods.
- If a Firebase major tier is ever pursued: expected prerequisites are iOS deployment target ≥ 15 (newer Google Firebase SDKs), compileSdk ≥ 35, AGP ≥ 8.5, and `pod install` revalidation of the GTMSessionFetcher resolution surface. Bundle these into the green-lit effort — not autonomous.

---

## 6. Recommendation summary

- ✅ Executed now: safe tier (within-constraint patch/minor). Committed with lockfile.
- ⏸ Controlled next (not now, no per-request): camera 0.12, flutter_lints 6, AGP/compileSdk modernization, google_sign_in 7.
- 🚫 Do not touch without explicit go: Firebase majors (all 4), google_sign_in 7 — full-risk pass required.

*Nothing in this phase changes Firebase/Supabase projects (constraint 4) — Supabase endpoint/key are untouched; the lockfile is the only tracked change.*