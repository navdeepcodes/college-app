# Phase 15 — Native build blockers investigation

**Date:** 2026-09-13, updated 2026-09-14 (Phase 18)
**Scope:** What breaks a native Android/iOS build today.

**Update (Phase 18):** the original version of this doc was read-only inspection — `flutter
build apk` was never actually run, only inferred. It was actually run this phase. That
surfaced two real blockers this doc had missed entirely (§0 below) underneath the
already-known google-services.json gap — the build never even reached the point where a
missing JSON would matter. One (§0.1) is fixed. One (§0.2) is a genuine version-compatibility
issue that needs a deliberate, tested decision, not a guess made under time pressure — left
for the user per the "don't blindly upgrade" constraint.

---

## ANDROID — verified by actually running `flutter build apk --debug` (Phase 18)

### 0.1 [FIXED] `android/settings.gradle.kts` / `android/app/build.gradle.kts` never wired the Flutter Gradle plugin at all

Before any other issue could even surface, the build failed immediately with:

```
[!] Your app is using an unsupported Gradle project. To fix this problem, create a new
project by running `flutter create -t app <app-directory>` and then move the dart code,
assets and pubspec.yaml to the new project.
```

Root cause: current Flutter (3.38.5) requires the declarative Flutter Gradle plugin —
`pluginManagement { includeBuild("$flutterSdkPath/packages/flutter_tools/gradle") }` plus
`id("dev.flutter.flutter-plugin-loader")` in `settings.gradle.kts`, and
`id("dev.flutter.flutter-gradle-plugin")` plus a `flutter { source = "../.." }` block in
`app/build.gradle.kts`. This project's Gradle scaffold predated that convention and had
**none** of it — confirmed pre-existing (reproduced identically on the pre-Phase-18 commit via
`git stash`), not something this session introduced.

**Fixed**, checked against the exact templates shipped in the installed Flutter SDK
(`packages/flutter_tools/templates/app/android-kotlin.tmpl/`), not guessed from memory. The
project's existing customizations (applicationId, compileSdk/minSdk/targetSdk, multidex, the
custom Flutter-engine-artifacts maven repo) were preserved, not replaced with template
defaults.

### 0.2 [BLOCKED — needs a deliberate version decision, not applied] Kotlin/AGP toolchain incompatibility

With 0.1 fixed, the build gets further and fails differently:

```
* Where: Build file '.../android/app/build.gradle.kts' line: 4
* What went wrong:
An exception occurred applying plugin request [id: 'org.jetbrains.kotlin.android', version: '1.9.24']
> Failed to apply plugin 'org.jetbrains.kotlin.android'.
   > Could not create an instance of type org.jetbrains.kotlin.gradle.plugin.mpp.KotlinAndroidTarget.
      > Could not generate a decorated class for type KotlinAndroidTarget.
         > com/android/build/gradle/api/BaseVariant
```

This is Kotlin Gradle Plugin 1.9.24 failing to load against AGP 8.2.2 / Gradle 8.4 as
installed on this machine's toolchain (Android SDK 36.1.0, build-tools 36.1.0 — `flutter
doctor` confirms these are current). This class of failure is a known AGP/Kotlin-plugin
version-compatibility break, not a config typo.

**Why not fixed here:** the correct remedy is bumping AGP + Kotlin Gradle Plugin (and likely
the Gradle wrapper) to a mutually-compatible modern trio — exactly the "major dependency
upgrade with migration risk" the standing constraints say to defer to a dedicated, tested
session rather than guess at under time pressure inside a broader hardening pass. Doing it
blind, with no device/emulator smoke test afterward, risks trading one broken build for a
differently-broken one.

**Recommended next step (human-directed session):** bump `com.android.application` /
`com.android.library` and `org.jetbrains.kotlin.android` in `android/settings.gradle.kts` to a
verified-compatible pair for Gradle 8.4 (or bump the Gradle wrapper too), then re-run `flutter
build apk --debug` and fix forward from whatever the next error is — do this as its own
focused piece of work with a real device/emulator check afterward, not folded into an
unrelated feature change.

### 1. `google-services.json` is missing while the google-services Gradle plugin is applied — HARD BUILD FAILURE (still applies, once 0.2 is resolved)

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

### 2. Everything else Android

- Kotlin DSL template; Java 17 toolchain (`build.gradle.kts`). AGP 8.2.2 / Kotlin 1.9.24 are
  the versions actually incompatible per §0.2 above — not "coherent" as this doc previously
  (incorrectly, without having run a build) claimed.
- `compileSdk 34 / targetSdk 34 / minSdk (flutter.minSdkVersion)`, `multiDexEnabled = true`.
- `namespace == applicationId == com.navdeep.collegeapp.college_app`.
- Phase 13 removed the camera/video_player/path_provider/firebase_messaging plugins, then
  Phase 17/18 restored camera + video_player (Moments was reinstated, gated behind
  `kMomentsEnabled = false` — see docs/phase17-moments-restoration.md). Their Android/iOS
  plugin registrants were already present in the committed `GeneratedPluginRegistrant` files
  before this session (Phase 13's "0 references on all platforms" claim only actually held for
  macOS — its own diff only touched the macOS registrant).
- Phase 18 also added release-signing scaffolding (`android/key.properties`-based, git-ignored,
  falls back to debug signing when absent — see `android/app/build.gradle.kts`). No keystore
  was created or committed; generating one is a human action.

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