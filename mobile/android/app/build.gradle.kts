plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Push notifications (audit 4.4.1) — google-services.json is a real
// Firebase project's config, which nothing in this repo can generate on
// its own (see docs/push_notifications_setup.md for the one-time manual
// step of dropping it in here). The google-services Gradle plugin
// itself throws a hard build failure — "File google-services.json is
// missing from module root folder" — the moment it's *applied* against
// a module that doesn't have one, well before firebase_core's own Dart-
// side init() ever gets a chance to run and degrade gracefully (see
// PushNotificationManager.init's own try/catch on that). Declaring it
// in the `plugins {}` block above like the two plugins before it would
// apply it unconditionally and break every build on this machine until
// that file exists — conditional `apply()` here instead, guarded on the
// file actually being present, so a checkout with no Firebase project
// configured yet still builds and runs (just without push).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.example.seenly"
    // Pinned explicitly rather than left as `flutter.compileSdkVersion` —
    // that default tracks whatever this machine's Flutter SDK ships
    // with, and on an older Flutter install it resolves too low for
    // several plugins here. Bumped from 35 to 36 after `flutter run`
    // itself reported app_links, flutter_plugin_android_lifecycle,
    // image_picker_android, shared_preferences_android, and
    // url_launcher_android all requiring SDK 36 — these are backward
    // compatible, so compiling against the highest one any plugin
    // needs is the right fix rather than picking one plugin's number.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.seenly"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Same reasoning as compileSdk above — targetSdk can't exceed
        // compileSdk.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
