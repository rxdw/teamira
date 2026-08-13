allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Forces compileSdk 36 on every Android subproject, including plugins
// pulled in from pub cache — app/build.gradle.kts's own compileSdk=36
// only governs the :app module itself, but android_play_install_referrer
// (see pubspec.yaml/REFERRAL_AND_PROFILE_SETUP.md) ships its own
// android/build.gradle hardcoding compileSdk 33, which :app's setting
// can't reach. That mismatch is exactly what
// ":android_play_install_referrer:checkDebugAarMetadata" was failing
// on — dependencies other, newer plugins (app_links, image_picker, ...)
// pull in now need API 34+, but that plugin's own module still
// compiles against 33 no matter what :app is set to.
//
// Reflection (rather than importing com.android.build.gradle.BaseExtension
// directly) because this root build script doesn't have the Android
// Gradle Plugin on its own classpath the way app/build.gradle.kts does
// — only individual subprojects apply that plugin. `afterEvaluate` so
// this runs once each subproject's own `android { ... }` block (which
// is what sets compileSdk in the first place) has already executed;
// running any earlier would just get immediately overwritten by that
// plugin's own hardcoded value again.
//
// Skips :app itself — it already sets compileSdk directly in its own
// app/build.gradle.kts, and by this point in the script :app has
// already been forced through full evaluation by the
// `evaluationDependsOn(":app")` block above (that's literally what
// evaluationDependsOn does — evaluates the target project immediately,
// synchronously). Calling afterEvaluate on an already-evaluated
// project is a hard Gradle error ("Cannot run Project.afterEvaluate
// (Action) when the project is already evaluated"), not just a no-op,
// so this has to actively skip it rather than relying on the
// afterEvaluate callback simply never firing.
subprojects {
    if (project.name == "app") return@subprojects
    afterEvaluate {
        extensions.findByName("android")?.let { androidExtension ->
            val setCompileSdk = androidExtension.javaClass.methods.firstOrNull {
                it.name == "compileSdkVersion" && it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            }
            setCompileSdk?.invoke(androidExtension, 36)
        }
    }
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
