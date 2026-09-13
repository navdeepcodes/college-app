pluginManagement {
    // Required by current Flutter (3.38.x) tooling — without this, `flutter
    // build`/`flutter run` refuse to build at all with "unsupported Gradle
    // project" and no other explanation. This project's settings.gradle.kts
    // predated the declarative Flutter Gradle plugin convention Flutter
    // introduced; everything else in this file's structure is otherwise
    // fine and preserved as-is.
    val flutterSdkPath = run {
        val props = java.util.Properties()
        file("local.properties").inputStream().use { props.load(it) }
        props.getProperty("flutter.sdk")
            ?: error("flutter.sdk not set in local.properties")
    }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// AGP 8.11.1 / Kotlin 2.2.20 (Gradle wrapper pinned to 8.14) is the EXACT
// version trio the currently-installed Flutter SDK's own `flutter create`
// template pins today for Flutter 3.38.5 — not a guess.
//
// These MUST be declared here, in a top-level `plugins{}` block with `apply
// false` — not merely inside `pluginManagement.plugins{}` (which only tells
// Gradle which version to use *if* something requests the id unversioned;
// it does not itself resolve/load the plugin classes). Declaring them only
// inside pluginManagement was the actual bug: AGP and the Kotlin Gradle
// Plugin ended up resolved into separate classloaders, and Kotlin's plugin
// failed applying with `NoClassDefFoundError: com/android/build/gradle/api/
// BaseVariant` — a real class, present in the correctly-resolved AGP jar
// (confirmed by inspecting it directly), just invisible from the wrong
// classloader. This is a known Gradle plugin-classloader-isolation failure
// mode (gradle/gradle#8411), not a version-compatibility gap: the identical
// error reproduced across three different AGP/Kotlin/Gradle version trios,
// including ones above Flutter's own documented minimum-supported floor,
// until this was restructured to match the stock template's approach —
// confirmed by generating a bare `flutter create` project on this same
// machine (same SDK/JDK/Gradle cache) and bisecting the two settings.gradle.kts
// files line-by-line until the exact difference was found.
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("com.android.library") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("com.google.gms.google-services") version "4.4.1" apply false
}

// No dependencyResolutionManagement block: this project had one declaring
// RepositoriesMode.PREFER_SETTINGS plus a custom "Flutter engine artifacts"
// maven repo at bin/cache/artifacts/engine/android/io/flutter/... — a path
// that has never existed in any installed Flutter SDK's actual cache layout
// (verified directly: the real layout is bin/cache/artifacts/engine/
// android-arm64 etc., flat per-ABI directories, not a maven-repo shape).
// Worse, PREFER_SETTINGS forces dependency resolution through ONLY the
// settings-declared repos, which silently blocked the modern Flutter
// Gradle plugin's own correct, built-in repository wiring for these
// `io.flutter:*_debug` engine artifacts — causing every debug build to
// fail with "Could not find io.flutter:armeabi_v7a_debug:...". The stock
// `flutter create` template has no dependencyResolutionManagement block at
// all; removing this one (not a "random" change — the path it referenced
// was simply never real) restores the plugin's default, working behavior.
rootProject.name = "college_app"
include(":app")
