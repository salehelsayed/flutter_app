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
val enableGroupMedia269DisposableProof =
    when (
        val raw = providers.gradleProperty(
            "enableGroupMedia269DisposableProof"
        ).orNull
    ) {
        null, "false" -> false
        "true" -> true
        else -> throw GradleException(
            "enableGroupMedia269DisposableProof must be exactly true or false."
        )
    }
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
val enableGroupExitReleaseDiagnosticsProof =
    when (
        val raw = providers.gradleProperty(
            "enableGroupExitReleaseDiagnosticsProof"
        ).orNull
    ) {
        null, "false" -> false
        "true" -> true
        else -> throw GradleException(
            "enableGroupExitReleaseDiagnosticsProof must be exactly true or false."
        )
    }
if (
    enableGroupMedia269DisposableProof &&
    (
        androidApplicationId != "com.mknoon.sims.groupmedia269" ||
            !disableGoogleServicesForDisposableProof
    )
) {
    throw GradleException(
        "The group-media 269 proof requires the exact disposable application " +
            "ID com.mknoon.sims.groupmedia269 with Google services disabled."
    )
}
if (
    enableGroupExitReleaseDiagnosticsProof &&
    (
        androidApplicationId != "com.mknoon.app.pb266proof" ||
            !disableGoogleServicesForDisposableProof
    )
) {
    throw GradleException(
        "The group-exit release diagnostics proof requires the exact disposable " +
            "application ID com.mknoon.app.pb266proof with Google services disabled."
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
val simsAndroidAbi =
    when (val raw = providers.gradleProperty("simsAndroidAbi").orNull?.trim()) {
        null, "" -> null
        "arm64-v8a" -> raw
        else -> throw GradleException(
            "simsAndroidAbi must be exactly arm64-v8a when supplied."
        )
    }

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
        if (enableGroupExitReleaseDiagnosticsProof) {
            testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        }
        buildConfigField(
            "boolean",
            "ENABLE_GROUP_EXIT_RELEASE_DIAGNOSTICS_PROOF",
            enableGroupExitReleaseDiagnosticsProof.toString()
        )
    }

    // Flutter Driver cannot attach to non-web release builds. The Android
    // instrumentation runner is enabled only for the PB266 release proof and
    // executes the same Dart integration target inside a true release APK.
    testBuildType = if (enableGroupExitReleaseDiagnosticsProof) {
        "release"
    } else {
        "debug"
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
        if (enableGroupExitReleaseDiagnosticsProof) {
            getByName("androidTest") {
                java.srcDir("src/groupExitReleaseDiagnosticsAndroidTest/java")
            }
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }

    buildTypes {
        getByName("debug") {
            simsAndroidAbi?.let { abi ->
                ndk {
                    abiFilters.clear()
                    abiFilters.add(abi)
                }
            }
        }
        release {
            when {
                hasReleaseSigning -> signingConfig = signingConfigs.getByName("release")
                allowDebugSigningInRelease -> signingConfig = signingConfigs.getByName("debug")
            }
            if (enableGroupExitReleaseDiagnosticsProof) {
                proguardFiles(
                    "src/groupExitReleaseDiagnostics/proguard-rules.pro"
                )
            }
        }
    }
}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Plan 329: the app-owned FCM service subclasses FlutterFire's service.
    // firebase_messaging keeps this dependency non-transitive at the app
    // compile boundary, so declare the already-resolved SDK version directly.
    implementation("com.google.firebase:firebase-messaging:24.1.2")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    implementation("com.google.guava:guava:33.3.1-android")
    // 180: pure-Java mDNS resolver. NsdManager intermittently never completes an
    // iOS `.local`-hostname _mknoon._tcp service; jmDNS binds to the WiFi
    // interface + does its own SRV/TXT/A resolution. See MdnsResolver.kt.
    implementation("org.jmdns:jmdns:3.5.9")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.13")
    testImplementation("androidx.work:work-testing:2.11.2")
    if (enableGroupExitReleaseDiagnosticsProof) {
        // `integration_test` is a dev plugin and Flutter intentionally omits
        // dev plugins from releaseApi. The proof property opts this one plugin
        // into both the tested release app and its instrumentation classpath.
        releaseImplementation(project(":integration_test"))
        releaseImplementation("androidx.test:runner:1.6.2")
        releaseImplementation("androidx.test:rules:1.6.1")
        releaseImplementation("androidx.test.espresso:espresso-core:3.6.1")
        androidTestImplementation("androidx.test:runner:1.6.2")
        androidTestImplementation("androidx.test:rules:1.6.1")
        androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    }
}

// A valid AAR is a non-empty zip; 1 KB threshold catches 0-byte stubs.
fun isValidAar(f: File): Boolean = f.exists() && f.length() > 1024

tasks.register("buildGoAar") {
    val aar = file("libs/GoMknoon.aar")
    val sourcesJar = file("libs/GoMknoon-sources.jar")
    val goRoot = rootProject.file("../go-mknoon")
    val bindingInputsScript = rootProject.file("../scripts/gomobile_binding_inputs.sh")
    val ensureBindingsScript = rootProject.file("../scripts/ensure_go_android_bindings.sh")
    val verifyBindingsScript = rootProject.file("../scripts/verify_gomobile_bindings.sh")
    val bindingInputStamp = file("libs/GoMknoon.inputs.sha256")
    val goInputs = fileTree(goRoot) {
        include("**/*.go", "go.mod", "go.sum")
        exclude("**/*_test.go")
    }
    val kotlinBridgeInputs = fileTree("src/main/kotlin") {
        include("**/GoBridge.kt")
    }

    inputs.files(goInputs)
    inputs.files(kotlinBridgeInputs)
    inputs.file(bindingInputsScript)
    inputs.file(ensureBindingsScript)
    inputs.file(verifyBindingsScript)
    outputs.file(aar)
    outputs.file(sourcesJar)
    outputs.file(bindingInputStamp)
    // Always execute the cheap deterministic digest check. The ensure script
    // invokes gomobile only when source or toolchain identity has changed.
    outputs.upToDateWhen { false }
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

if (
    (!hasGoogleServicesConfig || disableGoogleServicesForDisposableProof) &&
    !enableGroupExitReleaseDiagnosticsProof
) {
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
