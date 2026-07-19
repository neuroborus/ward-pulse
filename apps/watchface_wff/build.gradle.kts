plugins {
    id("com.android.application") version "9.3.0"
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
        minSdk = 33
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        debug {
            isMinifyEnabled = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = false
        }
    }
}
