import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// One key signs all three WardPulse packages. The phone and the Wear app share
// `app.wardpulse`, and Play refuses to install one over the other unless their
// signatures match; the watch face ships beside them from the same owner. The
// key lives at the repository root in an ignored `key.properties` whose
// `storeFile` points outside the tree, so nothing secret sits in a package.
// Creating it: docs/product/RELEASE_CHECKLIST.md, Signing.
// `android/` is two levels under the repository root and is this build's root
// project, hence the third `..`.
val releaseKeyFile = rootProject.file("../../../key.properties")
val releaseKey = Properties()
val hasReleaseKey = releaseKeyFile.exists()
if (hasReleaseKey) {
    releaseKeyFile.inputStream().use { releaseKey.load(it) }
}

// Absence is fatal only for a build that asked to be publishable, which the
// `wardpulseRequireReleaseKey` property marks; `just bundle-phone` sets it
// through `ORG_GRADLE_PROJECT_wardpulseRequireReleaseKey`, the one form both
// Gradle and the Flutter tool pass through. Otherwise a release build continues
// on the debug key and says so: an unannounced debug-signed release is how the
// TODO that used to sit here survived three months. The warning is scoped to
// release tasks because one that fired on every debug build and test run would
// teach its reader to ignore it, which is the same silence by another route.
if (!hasReleaseKey) {
    if (providers.gradleProperty("wardpulseRequireReleaseKey").isPresent) {
        throw GradleException(
            "A publishable build needs the release key, and ${releaseKeyFile.path} is missing. " +
                "Create it as docs/product/RELEASE_CHECKLIST.md describes under Signing.",
        )
    }
    if (gradle.startParameter.taskNames.any { it.contains("elease") }) {
        logger.warn(
            "WardPulse: no key.properties at the repository root, so this release build is " +
                "signed with the debug key and is NOT publishable.",
        )
    }
}

android {
    namespace = "app.wardpulse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Demanded by the flutter_local_notifications AAR, whose scheduling API
        // is built on java.time. WardPulse posts immediately and wakes through
        // WorkManager instead, but the requirement is on the library, not on
        // how much of it we use.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "app.wardpulse"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.clear()
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // A local release build still works without the key, because that is
            // what `flutter run --release` is for; the warning above says what it
            // produced.
            signingConfig =
                if (hasReleaseKey) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
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

dependencies {
    implementation("com.google.android.gms:play-services-wearable:20.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
