import com.android.apksig.ApkVerifier
import com.android.build.api.attributes.BuildTypeAttr
import com.android.build.api.variant.BuiltArtifactsLoader
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.security.KeyStore
import java.security.MessageDigest
import java.util.Properties
import javax.inject.Inject
import org.gradle.process.ExecOperations

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

abstract class PrepareDefaultWatchFace : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val apkArtifacts: ConfigurableFileCollection

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val validatorFiles: ConfigurableFileCollection

    @get:Input
    abstract val validatorSha256: Property<String>

    @get:Input
    abstract val clientPackageName: Property<String>

    @get:Input
    abstract val hostCertificateSha256: Property<String>

    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val javaExecutable: RegularFileProperty

    @get:Input
    abstract val javaRuntimeVersion: Property<String>

    @get:Internal
    abstract val builtArtifactsLoader: Property<BuiltArtifactsLoader>

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Internal
    abstract val assetsDirectory: DirectoryProperty

    @get:Internal
    abstract val resourcesDirectory: DirectoryProperty

    @get:Inject
    abstract val execOperations: ExecOperations

    companion object {
        fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(bytes).joinToString("") { "%02x".format(it) }

        fun hostCertificate(store: File?, password: String?, alias: String?): String {
            try {
                require(store != null && password != null && alias != null)
                val keyStore = KeyStore.getInstance(store, password.toCharArray())
                return sha256(requireNotNull(keyStore.getCertificate(alias)).encoded)
            } catch (_: Exception) {
                throw GradleException("Could not read the host signing certificate for Push separation.")
            }
        }
    }

    @TaskAction
    fun prepare() {
        val output = outputDirectory.get().asFile
        // No previous token may remain available after a failed validation.
        if (output.exists() && !output.deleteRecursively()) {
            throw GradleException("Could not invalidate the bundled watch face outputs.")
        }
        val staging = temporaryDir.resolve("validated-bundle")
        staging.deleteRecursively()
        try {
            val validator = validatorFiles.singleFile
            if (sha256(validator.readBytes()) != validatorSha256.get()) {
                throw GradleException("Watch Face Push validator checksum mismatch.")
            }
            val artifacts = builtArtifactsLoader.get().load(apkArtifacts)
                ?: throw GradleException("Missing Push APK metadata.")
            val artifact = artifacts.elements.singleOrNull()
                ?: throw GradleException("Exactly one Push APK is required.")
            if (artifacts.applicationId != "${clientPackageName.get()}.watchfacepush.main" ||
                (artifact.versionCode ?: 0) <= 0
            ) {
                throw GradleException("Unexpected Push APK identity or version.")
            }
            val assets = staging.resolve("assets").apply { mkdirs() }
            val apk = assets.resolve("default_watchface.apk")
            File(artifact.outputFile).copyTo(apk)
            val apkSha256 = sha256(apk.readBytes())
            val signature = ApkVerifier.Builder(apk).build().verify()
            val certificate = signature.signerCertificates.singleOrNull()
            if (!signature.isVerified || certificate == null) {
                throw GradleException("The bundled Push APK must have one valid signing certificate.")
            }
            if (sha256(certificate.encoded) == hostCertificateSha256.get()) {
                throw GradleException("The Push face and host app must use different signing certificates.")
            }

            // This CLI can return zero for failed checks. Require its success record and token too.
            // Capture both streams: tokens and raw validation output must not enter Gradle logs.
            val captured = ByteArrayOutputStream()
            val result = execOperations.exec {
                commandLine(
                    javaExecutable.get().asFile.absolutePath,
                    "-jar", validator.absolutePath,
                    "--apk_path", apk.absolutePath,
                    "--package_name", clientPackageName.get(),
                )
                standardOutput = captured
                errorOutput = captured
                isIgnoreExitValue = true
            }
            val lines = captured.toString(Charsets.UTF_8.name()).lineSequence().map { it.trim() }.toList()
            val prefix = "No failing checks detected, generated token: "
            val token = lines.filter { it.startsWith(prefix) }.singleOrNull()?.removePrefix(prefix)
            if (result.exitValue != 0 || lines.count { it == "Validation is successful" } != 1 ||
                lines.any { it == "Validation is unsuccessful" || it.startsWith("Failed check:") } ||
                // The pinned CLI emits a base64 MAC followed by a base64 validator version.
                token == null || !token.matches(Regex("[A-Za-z0-9+/]+={0,2}:[A-Za-z0-9+/]+={0,2}"))
            ) {
                throw GradleException("Official Watch Face Push validation failed; no bundle was generated.")
            }
            if (sha256(apk.readBytes()) != apkSha256) {
                throw GradleException("Push APK changed during validation.")
            }
            val values = staging.resolve("res/values").apply { mkdirs() }
            values.resolve("default_watchface.xml").writeText(
                """
                <?xml version="1.0" encoding="utf-8"?>
                <resources>
                    <string name="default_wf_token" translatable="false">$token</string>
                </resources>
                """.trimIndent() + "\n",
            )
            output.parentFile.mkdirs()
            Files.move(staging.toPath(), output.toPath())
        } catch (failure: Exception) {
            output.deleteRecursively()
            if (failure is GradleException) throw failure
            throw GradleException("Could not prepare the validated bundled watch face.")
        } finally {
            staging.deleteRecursively()
        }
    }
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
        minSdk = 33
        targetSdk = 36
        versionCode = 2
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
    implementation("androidx.wear.watchfacepush:watchfacepush:1.0.0")
    implementation("com.google.android.gms:play-services-wearable:20.0.1")

    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}

// Build-time only: one pinned official validator resolved through settings' Google Maven.
val pushValidator = configurations.create("pushValidator") {
    isCanBeConsumed = false
    isCanBeResolved = true
    isTransitive = false
}
dependencies.add(
    pushValidator.name,
    "com.google.android.wearable.watchface.validator:validator-push-cli:1.1.0-alpha01@jar",
)

androidComponents.onVariants { variant ->
    val kind = requireNotNull(variant.buildType)
    val capitalized = variant.name.replaceFirstChar { it.uppercaseChar() }
    val pushApk = configurations.create("${variant.name}PushApk") {
        isCanBeConsumed = false
        isCanBeResolved = true
        attributes {
            attribute(Usage.USAGE_ATTRIBUTE, objects.named("wardpulse-watchface-push-apk"))
            attribute(BuildTypeAttr.ATTRIBUTE, objects.named(kind))
        }
    }
    dependencies {
        add(pushApk.name, project(":watchface_push"))
    }

    val hostSigning = requireNotNull(android.buildTypes.getByName(kind).signingConfig)
    val hostStore = hostSigning.storeFile
    val hostPassword = hostSigning.storePassword
    val hostAlias = hostSigning.keyAlias
    val prepareFace = tasks.register<PrepareDefaultWatchFace>("prepare${capitalized}DefaultWatchFace") {
        apkArtifacts.from(pushApk)
        validatorFiles.from(pushValidator)
        validatorSha256.set("04dc20a0994df3eaebf025e107f7589c147b2ce8a2c628745e01a5c0a63fe4dd")
        clientPackageName.set(variant.applicationId)
        builtArtifactsLoader.set(variant.artifacts.getBuiltArtifactsLoader())
        // AGP provisions the conventional host debug identity if it is not present yet.
        // This prerequisite reads its actual certificate without a host-APK dependency cycle.
        dependsOn("validateSigning$capitalized")
        hostCertificateSha256.set(providers.provider {
            PrepareDefaultWatchFace.hostCertificate(hostStore, hostPassword, hostAlias)
        })
        javaExecutable.set(File(System.getProperty("java.home"), "bin/java"))
        javaRuntimeVersion.set(System.getProperty("java.runtime.version"))
        outputDirectory.set(layout.buildDirectory.dir("generated/defaultWatchFace/${variant.name}"))
        assetsDirectory.set(outputDirectory.dir("assets"))
        resourcesDirectory.set(outputDirectory.dir("res"))
    }
    variant.sources.assets!!.addGeneratedSourceDirectory(prepareFace, PrepareDefaultWatchFace::assetsDirectory)
    variant.sources.res!!.addGeneratedSourceDirectory(prepareFace, PrepareDefaultWatchFace::resourcesDirectory)
}
