pluginManagement {
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