import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
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
    compileSdk = 34

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
