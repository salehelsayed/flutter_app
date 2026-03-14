import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use(::load)
    }
}

val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}

val androidApplicationId = providers.gradleProperty("androidApplicationId")
    .orElse(localProperties.getProperty("android.applicationId") ?: "com.mknoon.app")
    .get()
val hasGoogleServicesConfig = file("google-services.json").exists()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
val allowDebugSigningInRelease =
    providers.gradleProperty("allowDebugSigningInRelease").orNull == "true"

fun requireKeystoreProperty(name: String): String =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException(
            "Missing `$name` in android/key.properties for Android release signing."
        )

if (hasGoogleServicesConfig) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn(
        "google-services.json not found in android/app. " +
        "Android Firebase services will stay disabled until the file is added."
    )
}

android {
    namespace = "com.mknoon.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(requireKeystoreProperty("storeFile"))
                storePassword = requireKeystoreProperty("storePassword")
                keyAlias = requireKeystoreProperty("keyAlias")
                keyPassword = requireKeystoreProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        applicationId = androidApplicationId
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            when {
                hasReleaseSigning -> signingConfig = signingConfigs.getByName("release")
                allowDebugSigningInRelease -> signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

repositories {
    flatDir {
        dirs("libs")
    }
}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// A valid AAR is a non-empty zip; 1 KB threshold catches 0-byte stubs.
fun isValidAar(f: File): Boolean = f.exists() && f.length() > 1024

tasks.register("buildGoAar") {
    val aar = file("libs/GoMknoon.aar")
    val goMknoonDir = file("${rootProject.projectDir}/../go-mknoon")
    outputs.file(aar)
    onlyIf { !isValidAar(aar) }
    doLast {
        // Remove any stale/invalid artifact before building.
        if (aar.exists()) {
            logger.lifecycle("Removing invalid GoMknoon.aar (${aar.length()} bytes)...")
            aar.delete()
        }
        logger.lifecycle("GoMknoon.aar not found — building via 'make android'...")
        val goPath = providers.exec {
            commandLine("go", "env", "GOPATH")
        }.standardOutput.asText.get().trim()
        @Suppress("DEPRECATION")
        exec {
            workingDir = goMknoonDir
            environment("PATH", System.getenv("PATH") + ":" + goPath + "/bin")
            environment("ANDROID_HOME", android.sdkDirectory.absolutePath)
            commandLine("make", "android")
        }
        if (!isValidAar(aar)) {
            aar.delete()
            throw GradleException(
                "GoMknoon.aar missing or invalid after 'make android'.\n" +
                "Ensure Go and gomobile are installed:\n" +
                "  go install golang.org/x/mobile/cmd/gomobile@latest\n" +
                "  gomobile init"
            )
        }
    }
}

tasks.named("preBuild") {
    dependsOn("buildGoAar")
}

if (!hasReleaseSigning && !allowDebugSigningInRelease) {
    tasks.matching {
        it.name in setOf("assembleRelease", "bundleRelease", "packageRelease")
    }.configureEach {
        doFirst {
            throw GradleException(
                "Android release builds require android/key.properties.\n" +
                "Set storeFile, storePassword, keyAlias, and keyPassword.\n" +
                "Use -PallowDebugSigningInRelease=true only for local smoke builds."
            )
        }
    }
}

if (!hasGoogleServicesConfig) {
    tasks.matching {
        it.name in setOf("assembleRelease", "bundleRelease", "packageRelease")
    }.configureEach {
        doFirst {
            throw GradleException(
                "Android release builds require android/app/google-services.json.\n" +
                    "Keep the file out of git, but inject it locally or in CI before release builds."
            )
        }
    }
}

flutter {
    source = "../.."
}
