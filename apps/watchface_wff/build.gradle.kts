import java.util.Properties

plugins {
    id("com.android.application") version "9.3.0"
}

// A separate application id, so Play lists this on its own — but the same key as
// the phone and the Wear app, because one owner publishes all three and a watch
// face that changed hands mid-life cannot be updated. The key lives at the
// repository root in an ignored `key.properties` whose `storeFile` points
// outside the tree. Creating it: docs/product/RELEASE_CHECKLIST.md, Signing.
val releaseKeyFile = rootProject.file("../../key.properties")
val releaseKey = Properties()
val hasReleaseKey = releaseKeyFile.exists()
if (hasReleaseKey) {
    releaseKeyFile.inputStream().use { releaseKey.load(it) }
}

// Fatal for a build that asked to be publishable — `just bundle-watchface` sets
// `wardpulseRequireReleaseKey` — and otherwise a warning on release tasks only.
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
    enableKotlin = false
    namespace = "app.wardpulse.watchface"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "app.wardpulse.watchface"
        minSdk = 34
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
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
        debug {
            isMinifyEnabled = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = false
            signingConfig =
                if (hasReleaseKey) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}
