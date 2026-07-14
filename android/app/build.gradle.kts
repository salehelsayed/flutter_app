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
val disableGoogleServicesForDisposableProof =
    providers.gradleProperty("disableGoogleServicesForDisposableProof").orNull == "true"
val enablePictureInPictureEngineDetachProof =
    when (
        val raw = providers.gradleProperty(
            "enablePictureInPictureEngineDetachProof"
        ).orNull
    ) {
        null, "false" -> false
        "true" -> true
        else -> throw GradleException(
            "enablePictureInPictureEngineDetachProof must be exactly true or false."
        )
    }
val enablePictureInPictureInterruptionProof =
    when (
        val raw = providers.gradleProperty(
            "enablePictureInPictureInterruptionProof"
        ).orNull
    ) {
        null, "false" -> false
        "true" -> true
        else -> throw GradleException(
            "enablePictureInPictureInterruptionProof must be exactly true or false."
        )
    }
if (
    enablePictureInPictureEngineDetachProof &&
    androidApplicationId != "com.mknoon.app.pipproof"
) {
    throw GradleException(
        "Picture-in-picture engine-detach proof sources require the exact " +
            "disposable application ID com.mknoon.app.pipproof."
    )
}
if (
    enablePictureInPictureInterruptionProof &&
    androidApplicationId != "com.mknoon.app.pipproof"
) {
    throw GradleException(
        "Picture-in-picture interruption proof sources require the exact " +
            "disposable application ID com.mknoon.app.pipproof."
    )
}
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
val allowDebugSigningInRelease =
    providers.gradleProperty("allowDebugSigningInRelease").orNull == "true"

fun requireKeystoreProperty(name: String): String =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException(
            "Missing `$name` in android/key.properties for Android release signing."
        )

if (hasGoogleServicesConfig && !disableGoogleServicesForDisposableProof) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn(
        if (disableGoogleServicesForDisposableProof) {
            "Google services disabled for an explicitly disposable proof build."
        } else {
            "google-services.json not found in android/app. " +
                "Android Firebase services will stay disabled until the file is added."
        }
    )
}

android {
    namespace = "com.mknoon.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

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

    sourceSets {
        if (enablePictureInPictureEngineDetachProof) {
            getByName("debug") {
                java.srcDir("src/pipProof/kotlin")
                manifest.srcFile("src/pipProof/AndroidManifest.xml")
            }
        }
        if (enablePictureInPictureInterruptionProof) {
            getByName("androidTest") {
                java.srcDir("src/pipInterruptionProofAndroidTest/java")
                manifest.srcFile(
                    "src/pipInterruptionProofAndroidTest/AndroidManifest.xml"
                )
            }
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
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

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // 180: pure-Java mDNS resolver. NsdManager intermittently never completes an
    // iOS `.local`-hostname _mknoon._tcp service; jmDNS binds to the WiFi
    // interface + does its own SRV/TXT/A resolution. See MdnsResolver.kt.
    implementation("org.jmdns:jmdns:3.5.9")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.13")
}

// A valid AAR is a non-empty zip; 1 KB threshold catches 0-byte stubs.
fun isValidAar(f: File): Boolean = f.exists() && f.length() > 1024

tasks.register("buildGoAar") {
    val aar = file("libs/GoMknoon.aar")
    val sourcesJar = file("libs/GoMknoon-sources.jar")
    val goRoot = rootProject.file("../go-mknoon")
    val ensureBindingsScript = rootProject.file("../scripts/ensure_go_android_bindings.sh")
    val verifyBindingsScript = rootProject.file("../scripts/verify_gomobile_bindings.sh")
    val goInputs = fileTree(goRoot) {
        include("**/*.go", "go.mod", "go.sum")
        exclude("**/*_test.go")
    }
    val kotlinBridgeInputs = fileTree("src/main/kotlin") {
        include("**/GoBridge.kt")
    }

    inputs.files(goInputs)
    inputs.files(kotlinBridgeInputs)
    inputs.file(ensureBindingsScript)
    inputs.file(verifyBindingsScript)
    outputs.file(aar)
    outputs.file(sourcesJar)
    doLast {
        @Suppress("DEPRECATION")
        exec {
            workingDir = rootProject.projectDir
            commandLine("/bin/bash", ensureBindingsScript.absolutePath)
        }
        if (!isValidAar(aar)) {
            aar.delete()
            throw GradleException(
                "GoMknoon.aar missing or invalid after ensuring Android gomobile bindings.\n" +
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

if (!hasGoogleServicesConfig || disableGoogleServicesForDisposableProof) {
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
