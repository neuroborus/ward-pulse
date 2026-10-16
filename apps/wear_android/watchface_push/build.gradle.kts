import com.android.build.api.artifact.SingleArtifact
import com.android.build.api.attributes.BuildTypeAttr
import java.security.KeyStore
import java.util.Properties

plugins {
    id("com.android.application")
}

// These properties and identities belong to the operator, never to build/ or Source.
object PushSigning {
    fun load(file: File): Properties = Properties().apply {
        if (file.isFile) {
            try {
                file.inputStream().use { load(it) }
            } catch (_: Exception) {
                throw GradleException("Could not read Push signing configuration.")
            }
        }
    }

    fun certificate(properties: Properties, repository: File): ByteArray {
        try {
            val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
            require(required.all { !properties.getProperty(it).isNullOrBlank() })
            val configuredStore = File(properties.getProperty("storeFile"))
            require(configuredStore.isAbsolute)
            val store = configuredStore.canonicalFile
            require(store.isFile)
            require(!store.toPath().startsWith(repository.canonicalFile.toPath()))
            val keyStore = KeyStore.getInstance(
                store,
                properties.getProperty("storePassword").toCharArray(),
            )
            val alias = properties.getProperty("keyAlias")
            require(keyStore.getKey(alias, properties.getProperty("keyPassword").toCharArray()) != null)
            return requireNotNull(keyStore.getCertificate(alias)).encoded
        } catch (_: Exception) {
            // Keystore exceptions can contain aliases or paths; do not forward their details.
            throw GradleException("Push signing needs a valid private key outside the repository.")
        }
    }
}

abstract class RequirePushSigning : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val signingFiles: ConfigurableFileCollection

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val keyStores: ConfigurableFileCollection

    @get:Input
    abstract val signingKind: Property<String>

    @get:Internal
    abstract val repositoryDirectory: DirectoryProperty

    @TaskAction
    fun requireSigning() {
        val propertiesFile = signingFiles.files.single { it.name == "watchface-push-${signingKind.get()}.properties" }
        if (!propertiesFile.isFile) {
            throw GradleException(
                "Missing watchface-push-${signingKind.get()}.properties; see watchface_push/README.md.",
            )
        }
        val certificate = PushSigning.certificate(
            PushSigning.load(propertiesFile),
            repositoryDirectory.get().asFile,
        )
        if (signingKind.get() == "release") {
            val debugFile = signingFiles.files.single { it.name == "watchface-push-debug.properties" }
            if (debugFile.isFile) {
                val developmentCertificate = PushSigning.certificate(
                    PushSigning.load(debugFile),
                    repositoryDirectory.get().asFile,
                )
                if (certificate.contentEquals(developmentCertificate)) {
                    throw GradleException("Push release signing must differ from Push development signing.")
                }
            }
        }
    }
}

val pushRepositoryDirectory = rootProject.layout.projectDirectory.dir("../..")
val pushKeys = listOf("debug", "release").associateWith { kind ->
    PushSigning.load(pushRepositoryDirectory.file("watchface-push-$kind.properties").asFile)
}
val pushVersionCode = providers.gradleProperty("wardpulsePushVersionCode").map { value ->
    value.toIntOrNull()?.takeIf { it > 0 }
        ?: throw GradleException("wardpulsePushVersionCode must be a positive integer.")
}.orElse(1)

android {
    enableKotlin = false
    namespace = "app.wardpulse.watchfacepush.main"
    compileSdk {
        version = release(37) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "app.wardpulse.watchfacepush.main"
        minSdk = 34
        targetSdk = 36
        versionCode = pushVersionCode.get()
        versionName = "0.1.0"
    }

    sourceSets.getByName("main").res.setSrcDirs(listOf("../../watchface_wff/src/main/res"))

    signingConfigs {
        pushKeys.forEach { (kind, properties) ->
            create("push${kind.replaceFirstChar { it.uppercaseChar() }}") {
                storeFile = properties.getProperty("storeFile")?.let { File(it) }
                storePassword = properties.getProperty("storePassword")
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // A resource-only face has no debug code and must obey the Push APK allowlist.
            isDebuggable = false
            isMinifyEnabled = true
            signingConfig = signingConfigs.getByName("pushDebug")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("pushRelease")
        }
    }

    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}

androidComponents.onVariants { variant ->
    val kind = requireNotNull(variant.buildType)
    val capitalized = variant.name.replaceFirstChar { it.uppercaseChar() }
    val signingCheck = tasks.register<RequirePushSigning>("require${capitalized}PushSigning") {
        signingKind.set(kind)
        repositoryDirectory.set(pushRepositoryDirectory)
        val kinds = if (kind == "release") listOf("release", "debug") else listOf("debug")
        signingFiles.from(kinds.map { pushRepositoryDirectory.file("watchface-push-$it.properties") })
        keyStores.from(kinds.mapNotNull { pushKeys.getValue(it).getProperty("storeFile")?.let { path -> File(path) } })
    }
    variant.lifecycleTasks.registerPreBuild(signingCheck)

    // Export the signed APK directory, including AGP's built-artifact metadata, not an AAR.
    val apkElements = configurations.create("${variant.name}PushApkElements") {
        isCanBeConsumed = true
        isCanBeResolved = false
        attributes {
            attribute(Usage.USAGE_ATTRIBUTE, objects.named("wardpulse-watchface-push-apk"))
            attribute(BuildTypeAttr.ATTRIBUTE, objects.named(kind))
        }
    }
    artifacts.add(apkElements.name, variant.artifacts.get(SingleArtifact.APK)) {
        type = "directory"
    }
}
