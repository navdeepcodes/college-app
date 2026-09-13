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

    plugins {
        id("com.android.application") version "8.2.2"
        id("com.android.library") version "8.2.2"
        id("org.jetbrains.kotlin.android") version "1.9.24"
        id("com.google.gms.google-services") version "4.4.1"
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()

        // 🔥 Flutter engine artifacts
        maven {
            val flutterSdkPath = run {
                val props = java.util.Properties()
                file("local.properties").inputStream().use { props.load(it) }
                props.getProperty("flutter.sdk")
                    ?: error("flutter.sdk not set in local.properties")
            }
            url = uri("$flutterSdkPath/bin/cache/artifacts/engine/android")
        }
    }
}

rootProject.name = "college_app"
include(":app")