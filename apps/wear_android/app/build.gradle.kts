import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The same key as the phone, and that is not a convenience: this module shares
// `app.wardpulse` with the phone shell, so Play will not install one over the
// other unless their signatures match. The key lives at the repository root in
// an ignored `key.properties` whose `storeFile` points outside the tree.
// Creating it: docs/product/RELEASE_CHECKLIST.md, Signing.
val releaseKeyFile = rootProject.file("../../key.properties")
val releaseKey = Properties()
val hasReleaseKey = releaseKeyFile.exists()
if (hasReleaseKey) {
    releaseKeyFile.inputStream().use { releaseKey.load(it) }
}

// Fatal for a build that asked to be publishable — `just bundle-wear` sets
// `wardpulseRequireReleaseKey` — and otherwise a warning on release tasks only,
// so a debug-signed artefact is never mistaken for a shippable one.
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
    namespace = "app.wardpulse.wear"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "app.wardpulse"
        minSdk = 30
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
            signingConfig =
                if (hasReleaseKey) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    sourceSets {
        getByName("androidTest").assets.directories.add(
            "../../../fixtures/snapshots",
        )
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.06.00")

    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core:1.19.0")
    implementation("androidx.wear.compose:compose-material3:1.6.2")
    implementation("androidx.wear.compose:compose-navigation:1.6.2")
    implementation("androidx.wear.compose:compose-ui-tooling:1.6.2")
    implementation("androidx.wear.watchface:watchface-complications-data-source-ktx:1.2.1")
    implementation("com.google.android.gms:play-services-wearable:20.0.1")

    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}
