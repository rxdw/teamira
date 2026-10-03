pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Push notifications (audit 4.4.1) — reads android/app/google-services.json
    // at build time. `apply false` here, actually applied in
    // app/build.gradle.kts below (see that file's own comment) — same
    // two-step pattern as the two plugins above it, and for the same
    // reason: a version needs declaring exactly once, here, even though
    // only :app actually uses it.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
