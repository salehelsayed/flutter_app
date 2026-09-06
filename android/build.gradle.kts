import com.android.build.api.variant.LibraryAndroidComponentsExtension
import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val configuredVc204ProofBuildRoot =
    providers.gradleProperty("vc204ProofBuildRoot").orNull
val newBuildDir: Directory = if (configuredVc204ProofBuildRoot == null) {
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
} else {
    val proofBuildDir = rootProject.file(configuredVc204ProofBuildRoot).canonicalFile
    val proofMarker = proofBuildDir.parentFile.resolve(".vc204-proof-build-root")
    val forbiddenRoots = listOf(
        proofBuildDir.toPath().root.toFile().canonicalFile,
        rootProject.projectDir.canonicalFile,
        rootProject.projectDir.parentFile.canonicalFile,
        rootProject.file(System.getProperty("user.home")).canonicalFile,
    )
    require(proofBuildDir.name == "vc204-proof-gradle-build") {
        "vc204ProofBuildRoot must name the dedicated vc204-proof-gradle-build leaf"
    }
    require(
        forbiddenRoots.none { forbidden ->
            proofBuildDir == forbidden || forbidden.toPath().startsWith(proofBuildDir.toPath())
        },
    ) {
        "vc204ProofBuildRoot must not be a filesystem, repository, workspace, or home root/ancestor"
    }
    require(
        proofMarker.isFile &&
            proofMarker.readText().trim() == "vc204-proof-build-root-v1",
    ) {
        "vc204ProofBuildRoot requires its VC2-04 proof sentinel"
    }
    rootProject.layout.dir(
        providers.provider { proofBuildDir },
    ).get()
}
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    if (name == "app") {
        return@subprojects
    }

    plugins.withId("com.android.library") {
        if (name == "bonsoir_android") {
            // Bonsoir 5.x pins SDK 33, below its AndroidX dependencies' SDK 34
            // minimum. AGP 8.13 checks this for library modules as well.
            extensions.configure<LibraryAndroidComponentsExtension> {
                finalizeDsl { library ->
                    library.compileSdk = maxOf(library.compileSdk ?: 0, 34)
                }
            }
        }

        // Eagerly set JVM 11 — works for plugins that don't override compileOptions.
        extensions.findByType(LibraryExtension::class.java)?.compileOptions {
            sourceCompatibility = JavaVersion.VERSION_11
            targetCompatibility = JavaVersion.VERSION_11
        }

        // afterEvaluate overrides plugins that hardcode JVM 1.8 in their own
        // build.gradle (e.g. bonsoir_android 5.x).  Some plugins (e.g.
        // audio_session) finalise compileOptions before afterEvaluate — the
        // try/catch lets those keep the eagerly-set JVM 11 while still fixing
        // plugins that don't finalise.  Kotlin JVM target is always synced to
        // match the resolved Java target so there is never a mismatch.
        afterEvaluate {
            val libExt = extensions.findByType(LibraryExtension::class.java)
                ?: return@afterEvaluate
            try {
                libExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_11
                libExt.compileOptions.targetCompatibility = JavaVersion.VERSION_11
            } catch (_: Exception) {
                // Already finalised — Java stays at the eagerly-set JVM 11.
            }
            tasks.withType<KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(
                        JvmTarget.fromTarget(libExt.compileOptions.targetCompatibility.toString()),
                    )
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
