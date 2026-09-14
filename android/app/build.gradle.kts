import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // google-services plugin removed: the app no longer uses any Firebase
    // package (see docs/supabase-migration-status.md — full Dart-layer
    // cutover to Supabase). Applying this plugin with no Firebase SDK
    // consuming it served no purpose and would have required a real
    // android/app/google-services.json (never fabricated, never
    // available) just to build at all — removing it actually unblocks
    // the Android build rather than risking it.
    // Must come after the Android and Kotlin plugins. Was entirely missing —
    // see the comment in ../settings.gradle.kts.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: standard Flutter convention (see
// https://docs.flutter.dev/deployment/android#signing-the-app) — reads
// android/key.properties, which is git-ignored and NOT present in this
// repo. Generate a real upload keystore and create that file yourself
// (storePassword/keyPassword/keyAlias/storeFile) before a release build;
// until then this deliberately still falls back to debug signing rather
// than fail the build, but that fallback must not ship to the Play Store —
// see docs/phase15-native-build-blockers.md.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.navdeep.collegeapp.college_app"
    // Several plugins (app_links, camera_android_camerax, google_sign_in_android,
    // image_picker_android, shared_preferences_android, url_launcher_android,
    // video_player_android, flutter_plugin_android_lifecycle) require compiling
    // against SDK 36 — Gradle emitted an explicit warning naming each one.
    // compileSdk is backward-compatible with lower minSdk/targetSdk, so this
    // is a safe bump, not a behavior change.
    compileSdk = 36

    defaultConfig {
        applicationId = "com.navdeep.collegeapp.college_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        multiDexEnabled = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // The Flutter Gradle plugin's own defaults set isShrinkResources
            // = true unconditionally for release (FlutterPlugin.kt); AGP
            // rejects shrinkResources=true with minifyEnabled=false. This
            // project deliberately keeps minification off for now (Phase
            // 12/13 — no code-shrinking decision), so shrinkResources must
            // explicitly follow it rather than inherit Flutter's default.
            isShrinkResources = false
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
}

// Wires this module to the Flutter engine/plugins — required by the
// dev.flutter.flutter-gradle-plugin above; also missing entirely before.
flutter {
    source = "../.."
}
