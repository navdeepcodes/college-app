# Phase 15 — Native build blockers investigation

**Date:** 2026-09-13
**Scope:** Read-only investigation of what would break a native Android/iOS build today, so a
release build can be attempted with eyes open. **No build was executed** (see constraints
below) — this is the "know before you build" pass.

---

## ANDROID — BLOCKER (confirmed)

### 1. `google-services.json` is missing while the google-services Gradle plugin is applied — HARD BUILD FAILURE

- `android/app/build.gradle.kts:4` applies `id("com.google.gms.google-services")` (pinned at
  `4.4.1` in `android/settings.gradle.kts:12`).
- `android/app/google-services.json` **does not exist** (verified via Read).
- The `processDebugGoogleServices` / `processReleaseGoogleServices` tasks **fail the build**
  when the file is absent. Firebase runtime init is Dart-side
  (`lib/firebase_options.dart`), but the **plugin still demands the JSON at build time**.

**Root cause of why this slipped:** Phase 8's `flutter build bundle --debug` is a **Dart-only
compile** — it never invokes Gradle, so it silently passed. There is no evidence any native
Android build has succeeded on this machine in the recoverable history.

**Fix (user action, config not code):** download `google-services.json` for project
`navdeep-college-app` (Android package `com.navdeep.collegeapp.college_app`) from the
Firebase console and place it at `android/app/google-services.json`. It is the app's own
public client config — add to the repo after the user obtains it.

### 2. Everything else Android is coherent

- Kotlin DSL template; AGP 8.2.2; Kotlin 1.9.24; Java 17 toolchain (`build.gradle.kts`).
- `compileSdk 34 / targetSdk 34 / minSdk 23`, `multiDexEnabled = true`.
- `namespace == applicationId == com.navdeep.collegeapp.college_app`.
- Phase 13 removed the camera/video_player/path_provider/firebase_messaging plugins — their
  native registrations are gone, shrinking the Gradle surface (fewer NDK/ABI pieces).

### 3. Verification command (after the JSON lands)

```bash
flutter build apk --debug
```

---

## iOS — SOFT RISK (not yet a confirmed blocker)

- `ios/Podfile:2` leaves `platform :ios, '13.0'` **commented out**. Flutter 3.38 +
  `firebase_*` pods require iOS 13.0+; if the default from `flutter_ios_podfile_setup` does
  not satisfy a pod's requirement, `pod install` errors. Current Flutter templates default
  the minimum to 13.0, so this *usually* resolves itself — verify on the first `pod install`.
- `ios/Runner/GoogleService-Info.plist` is present and tracked (Phase 8) — iOS native config
  is not missing like Android's.
- No CocoaPods analytics, standard `use_frameworks!` — nothing unusual.

**Verification command (blocked on signing/mach):**
```bash
flutter build ios --simulator  # or: pod install && xcodebuild
```

**Doctor note (2026-09-13):** Xcode 26.1.1, CocoaPods 1.16.2 installed. The one `flutter doctor`
Xcode [!] is "Unable to get list of installed Simulator runtimes" — a simulator-catalog quirk,
not a build blocker; it affects `flutter run` device listing, not compilation.

---

## Recommended order to unblock a native build

1. Place `android/app/google-services.json` (user action).
2. `flutter build apk --debug` → fixes Android.
3. `flutter build ios --simulator` → surfaces any iOS pod/Deployment-target issue.
4. Only after both compile: consider the High-tier dependency majors (out of scope here).

---

## Why no build was attempted in this phase

The sprint constraints hold ("no giant refactor / no upgrades / don't break what
works"), and a native build cannot even start until step 1 — attempting one before the JSON
exists would only reproduce the known Gradle failure. This phase is the **evidence-gathering
half**; execution is gated on the user's `google-services.json`.