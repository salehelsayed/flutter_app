plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutter_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

flutter {
    source = "../.."
}
