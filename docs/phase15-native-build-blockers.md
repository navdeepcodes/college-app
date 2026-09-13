# Phase 15 — Native build blockers investigation

**Date:** 2026-09-13, updated 2026-09-14 (Phase 18), updated again 2026-09-14 (Phase 19)
**Scope:** What breaks a native Android/iOS build today.

**Phase 19 result: every structural Android Gradle issue is fixed and verified by actually
running the build repeatedly.** The build now proceeds through plugin resolution, dependency
resolution, and code compilation cleanly, and fails ONLY at the genuine, expected
`google-services.json` boundary — a real Firebase credential this session has no legitimate
access to (checked: `firebase projects:list` under the authenticated account shows unrelated
projects, not TrueKinn's). That is a human action, not a bug. See §1.

---

## ANDROID — four real, distinct structural bugs found and fixed (Phase 18–19), verified by actually running `flutter build apk --debug` repeatedly, not inferred

### 0.1 [FIXED, Phase 18] Flutter Gradle plugin was never wired at all

`android/settings.gradle.kts` / `android/app/build.gradle.kts` had none of the declarative
Flutter Gradle plugin wiring (`includeBuild(.../flutter_tools/gradle)`,
`dev.flutter.flutter-plugin-loader`, `dev.flutter.flutter-gradle-plugin`, `flutter { source }`)
that current Flutter (3.38.5) requires. Every build failed immediately with "unsupported
Gradle project" before anything else could even run. Fixed against the exact templates
shipped in the installed Flutter SDK.

### 0.2 [FIXED, Phase 19] Gradle plugin-classloader isolation — NOT a version incompatibility

With 0.1 fixed, every build failed with:

```
An exception occurred applying plugin request [id: 'org.jetbrains.kotlin.android', version: 'X']
> Failed to apply plugin 'org.jetbrains.kotlin.android'.
   > Could not create an instance of type org.jetbrains.kotlin.gradle.plugin.mpp.KotlinAndroidTarget.
      > Could not generate a decorated class for type KotlinAndroidTarget.
         > com/android/build/gradle/api/BaseVariant
```

Phase 18 initially treated this as a version-compatibility gap and deferred it. **That
diagnosis was wrong.** Phase 19 ran it down properly:

- The identical error reproduced across three different AGP/Kotlin/Gradle version trios
  (including the exact versions the currently-installed Flutter SDK's own `flutter create`
  template pins: AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.14) — ruling out "too old."
- A bare `flutter create` project on this same machine (same SDK/JDK/Gradle cache) built
  successfully at those exact versions — ruling out an environment-wide problem.
- The AGP jar in the local Gradle cache was inspected directly and does contain the
  "missing" `BaseVariant` class — ruling out a corrupted/truncated dependency.
- Transplanting college-app's entire `android/` directory into the working bare project
  reproduced the failure — isolating the cause to college-app's own Gradle files.
- Bisecting `settings.gradle.kts` line-by-line against the working template found it: AGP
  and Kotlin Android plugin versions were declared only inside `pluginManagement.plugins{}`
  (a version-resolution *hint*), never in a top-level `plugins{}` block with `apply false`
  (which actually resolves and loads the plugin classes at settings-evaluation time). Without
  that, AGP and the Kotlin Gradle Plugin ended up in separate classloaders — a known Gradle
  failure mode (gradle/gradle#8411), not a version mismatch.

**Fixed** by restructuring `settings.gradle.kts` to declare
`com.android.application`/`com.android.library`/`org.jetbrains.kotlin.android`/
`com.google.gms.google-services` in the top-level `plugins{}` block with `apply false`,
matching the proven-working stock template structure exactly. Versions were also bumped to
AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.14 (the current template defaults) as part of this fix,
since the redundant `pluginManagement.plugins{}` declarations are no longer the source of
truth for version pinning.

### 0.3 [FIXED, Phase 19] `isShrinkResources=true` (Flutter plugin default) conflicted with this project's deliberate `isMinifyEnabled=false`

With 0.1 and 0.2 fixed, the build failed with `EvalIssueException: Removing unused resources
requires unused code shrinking to be turned on`. The Flutter Gradle plugin unconditionally
sets `isShrinkResources = true` for the release build type; this project (Phase 12/13)
deliberately kept `isMinifyEnabled = false` (no code-shrinking decision yet), and AGP rejects
that combination. This was a real latent bug in the project's own release config, invisible
until the build got this far for the first time. Fixed by explicitly setting
`isShrinkResources = false` alongside the existing `isMinifyEnabled = false`, keeping the
deliberate "no shrinking yet" stance consistent.

### 0.4 [FIXED, Phase 19] A vestigial custom Maven repo pointed at a path that never existed, and silently broke the Flutter engine artifact resolution it was blocking

With 0.1–0.3 fixed, the build failed with `Could not find io.flutter:armeabi_v7a_debug:...`
(and the other per-ABI engine artifacts). `settings.gradle.kts` had a custom
`dependencyResolutionManagement { repositoriesMode.set(PREFER_SETTINGS); ... maven {
url = "$flutterSdkPath/bin/cache/artifacts/engine/android" } }` block. Verified directly: that
path has **never existed** in any installed Flutter SDK's actual cache layout (the real
layout is flat per-ABI directories like `engine/android-arm64`, not a Maven-repo shape).
Worse, `PREFER_SETTINGS` forced all dependency resolution through *only* the settings-declared
repos, which silently blocked the modern Flutter Gradle plugin's own correct, built-in
repository wiring for these artifacts. The bare stock template has no such block at all.
**Removed** — it was actively harmful, not merely redundant, since the path it referenced was
never real to begin with.

Also bumped `compileSdk` 34 → 36 in the same pass: Gradle explicitly warned that 8 plugins
(app_links, camera_android_camerax, google_sign_in_android, image_picker_android,
shared_preferences_android, url_launcher_android, video_player_android,
flutter_plugin_android_lifecycle) require it. Backward-compatible with the existing
`minSdk`/`targetSdk`, not a behavior change.

### 1. [REMAINING — genuine human action] `google-services.json` is missing

- `android/app/build.gradle.kts` applies `id("com.google.gms.google-services")`.
- `android/app/google-services.json` does not exist — confirmed, and correctly git-ignored
  (Phase 18 added it to `.gitignore` defensively).
- With every structural issue above fixed, this is now the **only** thing standing between a
  clean `flutter clean && flutter build apk --debug` and a working debug APK. Verified: the
  full build log is clean start to finish up to exactly this one task failure
  (`:app:processDebugGoogleServices`), with no other warnings or errors.
- Checked whether this session could legitimately retrieve one rather than fabricate it: the
  authenticated Firebase CLI (`firebase projects:list`) only has access to unrelated projects
  (Apostle, Huddle, Huddle Workspace) — not TrueKinn's real Firebase project. Per explicit
  instruction, no placeholder/fake file was created.

**Fix (human action, not code):** download `google-services.json` for the real TrueKinn
Firebase project (Android package `com.navdeep.collegeapp.college_app`) from the Firebase
console and place it at `android/app/google-services.json`. It is the app's own public client
config, safe to commit once obtained (it is not a secret credential the way a service-role
key is), though this repo currently keeps it git-ignored — either is a reasonable choice, just
be consistent.

### Verification command (after the JSON lands)

```bash
flutter clean && flutter build apk --debug
```

Expected: succeeds. Everything upstream of this exact task is now proven working on this
machine, repeatedly, with full clean rebuilds between attempts (not incremental-build luck).

---

## iOS — SOFT RISK (not yet a confirmed blocker, not attempted in Phase 19 — time)

- `ios/Podfile:2` leaves `platform :ios, '13.0'` **commented out**. Flutter 3.38 +
  `firebase_*` pods require iOS 13.0+; if the default from `flutter_ios_podfile_setup` does
  not satisfy a pod's requirement, `pod install` errors. Current Flutter templates default
  the minimum to 13.0, so this *usually* resolves itself — verify on the first `pod install`.
- `ios/Runner/GoogleService-Info.plist` is present and tracked, but (per the Phase 18 UI/
  platform audit) its `BUNDLE_ID`/`GOOGLE_APP_ID` don't match `lib/firebase_options.dart`'s iOS
  block — see that audit for exact values. Needs `flutterfire configure` with real console
  access to fix correctly; not attempted here for the same reason as google-services.json.
- No CocoaPods analytics, standard `use_frameworks!` — nothing unusual.

**Verification command (not yet run):**
```bash
flutter build ios --simulator  # or: pod install && xcodebuild
```

**Doctor note:** Xcode 26.1.1, CocoaPods 1.16.2 installed. The one `flutter doctor` Xcode [!]
is "Unable to get list of installed Simulator runtimes" — a simulator-catalog quirk, not a
build blocker; it affects `flutter run` device listing, not compilation.

---

## Recommended order to fully unblock

1. Place `android/app/google-services.json` (human action — the only remaining Android gap).
2. `flutter clean && flutter build apk --debug` → should now succeed end-to-end.
3. Run on a real device/emulator and do an actual smoke test — a successful build is not
   the same claim as "the app works."
4. `flutter build ios --simulator` after fixing the Firebase config mismatch above → surfaces
   any remaining iOS-specific issue.
5. Only after both platforms are confirmed working: consider the High-tier dependency majors
   (out of scope here, deliberately deferred).
