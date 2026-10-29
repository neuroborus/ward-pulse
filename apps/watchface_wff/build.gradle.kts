import java.util.Properties
import javax.inject.Inject
import org.gradle.process.ExecOperations

plugins {
    id("com.android.application") version "9.3.0"
}

abstract class GenerateN1PairDiagnostics : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val generator: RegularFileProperty

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val supportFiles: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Inject
    abstract val execOperations: ExecOperations

    @TaskAction
    fun generate() {
        execOperations.exec {
            commandLine(
                "node", generator.get().asFile.absolutePath, "--n1-pair-diagnostics-output",
                outputDirectory.file("raw/watchface.xml").get().asFile.absolutePath,
            )
        }
    }
}

val n1PairDiagnostics = providers.gradleProperty("wardpulseN1PairDiagnostics")
    .map { it.toBooleanStrict() }.getOrElse(false)
gradle.taskGraph.whenReady {
    if (n1PairDiagnostics && allTasks.any { it.name.contains("release", ignoreCase = true) }) {
        throw GradleException("wardpulseN1PairDiagnostics is debug-only; release requests are forbidden.")
    }
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
        versionCode = 2
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

// Register the resource source only while opted in, even if a previous overlay still exists.
androidComponents.onVariants(androidComponents.selector().withBuildType("debug")) { variant ->
    if (n1PairDiagnostics) {
        val overlay = tasks.register<GenerateN1PairDiagnostics>("generateN1PairDiagnostics") {
            generator.set(layout.projectDirectory.file("../../tools/render-watchface.mjs"))
            supportFiles.from(
                layout.projectDirectory.file("../../tools/check-watchface-structure.py"),
                layout.projectDirectory.file("../../tools/design-output.mjs"),
            )
            outputDirectory.set(layout.buildDirectory.dir("generated/n1PairDiagnostics/debug/res"))
        }
        variant.sources.res!!.addGeneratedSourceDirectory(overlay, GenerateN1PairDiagnostics::outputDirectory)
    }
}
